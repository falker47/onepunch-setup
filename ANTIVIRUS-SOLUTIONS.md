# Onepunch-setup - Soluzioni per problemi di Antivirus

## 🚨 Problema: "Il file è stato rilevato come virus"

Questo è un **falso positivo** comune con i file PowerShell compilati. Il software è completamente sicuro.

## ✅ Soluzioni

### 1. **Versione Portable (RACCOMANDATO)**
Usa il file `onepunch-setup-portable.ps1` invece dell'EXE:
```powershell
# Tasto destro → "Esegui con PowerShell" oppure:
powershell -ExecutionPolicy Bypass -File onepunch-setup-portable.ps1
```

### 2. **Esclusione temporanea dall'antivirus**

#### Windows Defender:
1. Apri **Windows Security** (cerca "Windows Security" nel menu Start)
2. Vai su **"Protezione da virus e minacce"**
3. Clicca su **"Gestisci impostazioni"** sotto "Impostazioni di protezione"
4. Scorri giù e clicca su **"Aggiungi o rimuovi esclusioni"**
5. Clicca **"Aggiungi un'esclusione"** → **"File"**
6. Seleziona il file `onepunch-setup.exe`

#### Altri Antivirus:
- **Avast**: Impostazioni → Protezione → Esclusioni
- **AVG**: Impostazioni → Protezione → Esclusioni  
- **Norton**: Impostazioni → Antivirus → Esclusioni
- **McAfee**: Impostazioni → Protezione → Esclusioni

### 3. **Scaricare direttamente da GitHub**
Se il file viene bloccato durante il download:
1. Vai su: https://github.com/falker47/onepunch-setup
2. Clicca su **"Releases"**
3. Scarica il file `.zip` o `.ps1`

## 🔍 Perché succede?

- **PowerShell compilato**: Gli antivirus sono cauti con PowerShell
- **Privilegi amministratore**: Richiede elevazione = più sospetto
- **Nessuna firma digitale**: File non firmati sono considerati rischiosi
- **Comportamento simile a malware**: Installa software = pattern sospetto

## 🛡️ Il software è sicuro perché:

- ✅ Codice sorgente pubblico su GitHub
- ✅ Solo usa `winget` (strumento ufficiale Microsoft)
- ✅ Non scarica nulla da fonti non verificate
- ✅ Non modifica il registro di sistema
- ✅ Non accede a dati personali

## 📞 Supporto

Se continui ad avere problemi:
1. Usa la versione portable (`onepunch-setup-portable.ps1`)
2. Contatta il supporto del tuo antivirus per segnalare il falso positivo
3. Apri un issue su GitHub: https://github.com/falker47/onepunch-setup/issues
