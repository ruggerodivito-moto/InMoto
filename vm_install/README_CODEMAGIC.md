# Configurazione Codemagic (da fare una volta sola, dal browser)

## 1. Crea account Codemagic

Vai su **https://codemagic.io** → **Sign in with GitHub**

---

## 2. Collega il repository InMoto

- Dashboard → **Add application**
- Seleziona il repository `InMoto` (deve essere pubblico)
- Seleziona **Flutter/Other** come tipo (poi userai il codemagic.yaml)

---

## 3. Collega il tuo Apple ID

- **Teams** (menu in alto) → seleziona il tuo team personale
- **Integrations** → **Apple Developer Portal** → **Connect**
- Inserisci la tua email Apple ID e la password
- ⚠️ Se hai la **verifica in due passi** attiva (quasi certamente):
  - Vai su **https://appleid.apple.com**
  - Entra → **Sicurezza** → **Password per le app** → Genera
  - Usa questa password "app-specific" in Codemagic al posto di quella normale

---

## 4. Registra il tuo iPhone

Codemagic ha bisogno dell'**UDID** del tuo iPhone per creare il profilo di provisioning.

**Trova l'UDID:**
```
iPhone → Impostazioni → Generali → Info → scorri in fondo → UDID
(tieni premuto per copiarlo)
```

In Codemagic:
- Vai su **InMoto** (la tua app) → **Environment variables**
- Aggiungi una variabile:
  - **Nome**: `REGISTERED_DEVICES`
  - **Valore**: il tuo UDID (es. `00008110-001234567890ABCE`)
  - **Gruppo**: `device_config` (o qualsiasi nome)

---

## 5. Trova i tuoi token

Per gli script della VM ti servono:

### Token API Codemagic
- **Teams** → seleziona team → **API token**
- Copia il token (inizia con lettere/numeri casuali)

### App ID Codemagic
- Vai su **https://codemagic.io/apps**
- Clicca su **InMoto**
- Guarda l'URL: `https://codemagic.io/app/`**QUESTO_E_L_ID**`/...`
- Copia l'ID (stringa di ~24 caratteri)

---

## 6. Avvia il primo build

- Dashboard Codemagic → **InMoto** → **Start new build**
- Branch: `main`
- Workflow: `ios-personal-free`
- Clicca **Start build**

Il build dura circa **15-20 minuti**.
Puoi seguire il log in tempo reale.

Quando finisce, il file `InMoto.ipa` appare nella sezione **Artifacts**.

---

## Nota: scadenza 7 giorni

Con un Apple ID gratuito, il certificato dura **7 giorni**.

- Ogni 7 giorni: esegui `bash 4_installa_ipa.sh` dalla VM (ricompila e reinstalla)
- Oppure installa **SideStore** sul telefono → gestisce il rinnovo automatico senza computer

### SideStore (opzionale, rinnovo automatico)
1. Apri **Safari** sull'iPhone → vai su `https://sidestore.io`
2. Installa SideStore (usa lo stesso Apple ID)
3. In SideStore → **Browse** → **+** → incolla:
   `https://raw.githubusercontent.com/TUO_USERNAME/InMoto/main/apps.json`
4. Installa InMoto da SideStore
5. **SideStore → Impostazioni → Enable WireGuard** → ON

Da questo momento SideStore rinnova automaticamente il certificato
ogni 7 giorni in background. Non devi fare nulla.
