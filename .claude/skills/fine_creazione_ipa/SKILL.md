---
name: fine_creazione_ipa
description: Procedura di rilascio InMoto dopo una modifica al codice Swift — commit, push, build su GitHub Actions, download IPA, installazione su iPhone via Sideloadly e verifica della versione installata. Usala ogni volta che hai finito di modificare il codice e devi portare la nuova versione sul telefono.
---

# Fine creazione IPA — rilascio e installazione InMoto

Procedura completa per portare una modifica del codice Swift fino all'app
installata e verificata sull'iPhone. Esegui i passi **in ordine**.

Contesto fisso del progetto:
- Repo GitHub: `ruggerodivito-moto/InMoto`, branch `main`.
- Bundle id installato (suffisso team Sideloadly): `com.divito.InMoto.3S34FCRGM2`.
- iPhone 15 Pro iOS 26.x, UDID `00008130-00022C8E0A51001C`, pairing già fatto.
- Python: usare **`py -3.12`** (il 3.14 di default non compila pymobiledevice3).
- Cartella download IPA: `C:\Users\divito_adm\Downloads\`.

---

## 1. Commit

Stage solo i file modificati e committa.

```bash
git add <file...>
git commit -m "<tipo>: <descrizione>

<corpo>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

⚠️ **Caveat PowerShell**: messaggi di commit che contengono `" / "` (spazio-slash-spazio)
possono far scattare un blocco di sicurezza fasullo ("Remove-Item on '/'").
Se capita, riformula il messaggio senza ` / `.

## 2. Pull rebase + push

Il bot di rilascio committa `chore: release ... [skip ci]` su `main` dopo ogni
build, quindi **fai sempre il rebase prima del push** o il push verrà rifiutato.

```bash
git pull --rebase origin main
git push origin main
git rev-parse HEAD          # ← SHA reale, serve dopo. MAI inventarlo.
```

## 3. Attendi la build su GitHub Actions

Il push fa partire `.github/workflows/release.yml`: builda l'IPA **non firmato**
su `macos-15` (~50-60 s) e pubblica la release `v1.0.<data>-<run>` con gli asset
`InMoto.ipa` (nome stabile) e `InMoto-<tag>.ipa` (versione nel nome).

Polla finché `completed`, usando lo **SHA reale** del passo 2:

```bash
SHA=<sha-da-git-rev-parse>
for i in $(seq 1 30); do
  R=$(curl -s "https://api.github.com/repos/ruggerodivito-moto/InMoto/actions/runs?head_sha=$SHA")
  STATUS=$(echo "$R" | python -c "import sys,json; d=json.load(sys.stdin); r=[x for x in d.get('workflow_runs',[]) if x['name']=='Build & Release IPA']; print((r[0]['status']+'|'+str(r[0]['conclusion'])) if r else 'pending|none')")
  echo "[$i] $STATUS"
  case "$STATUS" in completed*) break;; esac
  sleep 10
done
```

Se `completed|failure`: apri il log del run su GitHub e correggi prima di proseguire
(l'unico check di compilazione Swift è questa build — niente Xcode/swiftc in locale).

## 4. Scarica l'IPA

Leggi tag e nomi asset, poi scarica **entrambi** nei Download. Il file versionato
serve all'utente per riconoscere la versione in Sideloadly; `InMoto.ipa` resta come
nome stabile per SideStore/script.

```bash
curl -s "https://api.github.com/repos/ruggerodivito-moto/InMoto/releases/latest" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('tag:',d['tag_name']); [print(' -',a['name'],a['size']) for a in d['assets']]"

TAG=<tag>   # es. v1.0.20260611-24
curl -sL "https://github.com/ruggerodivito-moto/InMoto/releases/download/$TAG/InMoto-$TAG.ipa" \
  -o "C:/Users/divito_adm/Downloads/InMoto-$TAG.ipa" -w "%{http_code} %{size_download}\n"
curl -sL "https://github.com/ruggerodivito-moto/InMoto/releases/latest/download/InMoto.ipa" \
  -o "C:/Users/divito_adm/Downloads/InMoto.ipa" -w "%{http_code} %{size_download}\n"
```

Verifica che la dimensione scaricata coincida con `size` dell'asset nella release.

## 5. Installazione sull'iPhone (Sideloadly — manuale)

La firma+installazione avviene con **Sideloadly** (GUI,
`%LOCALAPPDATA%\Sideloadly\sideloadly.exe`, già installato). Non si può passare
l'IPA da riga di comando (errore "guru meditation … does not exist").

Guida l'utente a:
1. Assicurarsi che Sideloadly sia aperto (`Get-Process sideloadly,sideloadlydaemon`).
2. **Riselezionare** l'IPA versionato nella GUI: `C:\Users\divito_adm\Downloads\InMoto-<tag>.ipa`
   (va riselezionato anche se sembra già caricato).
3. Apple ID compilato, iPhone collegato via USB e sbloccato.
4. Premere **Start** → inserire password Apple ID / 2FA.

Se si blocca su **"Preparing Anisette 50%"**: killare `sideloadly` +
`sideloadlydaemon` e riaprire Sideloadly, poi ripetere.

Aspetta che l'utente confermi **"Done"** / "fatto" prima del passo 6.

## 6. Verifica versione installata

Confronta la `CFBundleVersion` installata con il numero di build atteso (il `<run>`
del tag, es. tag `…-24` → versione `24`):

```bash
py -3.12 -m pymobiledevice3 apps query com.divito.InMoto.3S34FCRGM2 2>&1 \
  | python -c "import sys,json; d=json.load(sys.stdin); v=list(d.values())[0] if isinstance(list(d.values())[0],dict) else d; print('CFBundleVersion installata:', v.get('CFBundleVersion','?'))"
```

- Se la versione **coincide** → installazione riuscita, comunica l'esito.
- Se è ancora la **precedente** → l'installazione Sideloadly non è andata a buon
  fine: rifai il passo 5 (riselezione IPA + Start).

---

## Diagnosi rapida

| Problema | Causa / fix |
|---|---|
| push rifiutato (`rejected`) | manca il rebase → `git pull --rebase origin main` |
| build `failure` | leggi il log del run su GitHub Actions |
| `apps query` dà JSON vuoto/errore | iPhone scollegato o bloccato; riconnetti e sblocca |
| versione non cambia dopo Start | Sideloadly non ha completato; riseleziona IPA e ripeti |
| pymobiledevice3 non parte | usa `py -3.12`, non `py` / `python` |
