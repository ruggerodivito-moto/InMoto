@echo off
:: InMoto Installer — Windows
:: Doppio click per avviare

title InMoto Installer

echo.
echo  Avvio InMoto Installer...
echo  (potrebbe apparire una finestra blu di Windows Security: clicca "Esegui comunque")
echo.

:: Esegui lo script PowerShell con bypass della policy di esecuzione
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0installa.ps1" -GithubUser "ruggerodivito-moto"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  Si e' verificato un errore. Premi un tasto per chiudere.
    pause > nul
)
