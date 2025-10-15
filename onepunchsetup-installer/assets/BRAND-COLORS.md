# 🎨 Palette Colori Onepunch-setup - Codice Pronto

## 🎯 Colori Principali del Brand

### Giallo Dorato (Colore Primario)
```css
/* CSS */
--primary-yellow: #FDCA56;
--primary-yellow-hover: #F4C430;
--primary-yellow-light: #FFD02F;
--primary-yellow-dark: #E6B800;

/* RGB */
RGB(253, 202, 86)
RGB(244, 196, 48)  /* Hover */
RGB(255, 208, 47)  /* Light */
RGB(230, 184, 0)   /* Dark */
```

### Rosso Acceso (Colore Secondario)
```css
/* CSS */
--secondary-red: #DB1E1F;
--secondary-red-hover: #C41E3A;
--secondary-red-light: #EF2422;
--secondary-red-dark: #B71C1C;

/* RGB */
RGB(219, 30, 31)
RGB(196, 30, 58)   /* Hover */
RGB(239, 36, 34)   /* Light */
RGB(183, 28, 28)   /* Dark */
```

### Nero (Colore Neutro)
```css
/* CSS */
--neutral-black: #000000;
--neutral-gray-dark: #333333;
--neutral-gray-medium: #666666;
--neutral-gray-light: #999999;

/* RGB */
RGB(0, 0, 0)
RGB(51, 51, 51)    /* Dark Gray */
RGB(102, 102, 102) /* Medium Gray */
RGB(153, 153, 153) /* Light Gray */
```

## 🎨 Palette Completa per UI

### Colori di Background
```css
--bg-primary: #FDCA56;      /* Giallo dorato */
--bg-secondary: #DB1E1F;     /* Rosso acceso */
--bg-neutral: #F5F5F5;      /* Grigio chiaro */
--bg-dark: #000000;         /* Nero */
--bg-card: #FFFFFF;         /* Bianco per card */
```

### Colori di Testo
```css
--text-primary: #000000;    /* Nero su sfondo chiaro */
--text-secondary: #FDCA56;  /* Giallo su sfondo scuro */
--text-muted: #666666;      /* Grigio per testi secondari */
--text-white: #FFFFFF;      /* Bianco su sfondo scuro */
```

### Colori di Stato
```css
--success: #4CAF50;         /* Verde successo */
--warning: #FF9800;         /* Arancione warning */
--error: #DB1E1F;           /* Rosso errore (brand) */
--info: #2196F3;            /* Blu info */
```

## 🎯 Implementazione WPF/XAML

### Brush Resources
```xml
<!-- Colori principali -->
<SolidColorBrush x:Key="PrimaryYellow" Color="#FDCA56"/>
<SolidColorBrush x:Key="PrimaryYellowHover" Color="#F4C430"/>
<SolidColorBrush x:Key="SecondaryRed" Color="#DB1E1F"/>
<SolidColorBrush x:Key="SecondaryRedHover" Color="#C41E3A"/>
<SolidColorBrush x:Key="NeutralBlack" Color="#000000"/>

<!-- Colori di background -->
<SolidColorBrush x:Key="BackgroundPrimary" Color="#FDCA56"/>
<SolidColorBrush x:Key="BackgroundSecondary" Color="#DB1E1F"/>
<SolidColorBrush x:Key="BackgroundNeutral" Color="#F5F5F5"/>
<SolidColorBrush x:Key="BackgroundCard" Color="#FFFFFF"/>

<!-- Colori di testo -->
<SolidColorBrush x:Key="TextPrimary" Color="#000000"/>
<SolidColorBrush x:Key="TextSecondary" Color="#FDCA56"/>
<SolidColorBrush x:Key="TextMuted" Color="#666666"/>
<SolidColorBrush x:Key="TextWhite" Color="#FFFFFF"/>
```

## 🎨 Implementazione PowerShell

### Variabili Colori
```powershell
# Colori principali
$PrimaryYellow = "#FDCA56"
$PrimaryYellowHover = "#F4C430"
$SecondaryRed = "#DB1E1F"
$SecondaryRedHover = "#C41E3A"
$NeutralBlack = "#000000"

# Colori di background
$BackgroundPrimary = "#FDCA56"
$BackgroundSecondary = "#DB1E1F"
$BackgroundNeutral = "#F5F5F5"
$BackgroundCard = "#FFFFFF"

# Colori di testo
$TextPrimary = "#000000"
$TextSecondary = "#FDCA56"
$TextMuted = "#666666"
$TextWhite = "#FFFFFF"
```

## 🎯 Suggerimenti di Utilizzo

### Per Bottoni:
- **Primario:** Background `#FDCA56`, Testo `#000000`
- **Secondario:** Background `#DB1E1F`, Testo `#FFFFFF`
- **Hover:** Versione più scura del colore base

### Per Card/Pannelli:
- **Background:** `#FFFFFF` con bordo `#FDCA56`
- **Ombra:** Grigio chiaro `#E0E0E0`

### Per Testi:
- **Titoli:** `#000000` (nero)
- **Sottotitoli:** `#666666` (grigio)
- **Link:** `#DB1E1F` (rosso brand)
- **Su sfondo scuro:** `#FDCA56` (giallo)

### Per Stati:
- **Successo:** Verde `#4CAF50`
- **Errore:** Rosso brand `#DB1E1F`
- **Warning:** Arancione `#FF9800`
- **Info:** Blu `#2196F3`

## 🎨 Palette Gradiente

### Gradiente Primario
```css
background: linear-gradient(135deg, #FDCA56 0%, #F4C430 100%);
```

### Gradiente Secondario
```css
background: linear-gradient(135deg, #DB1E1F 0%, #C41E3A 100%);
```

### Gradiente Neutro
```css
background: linear-gradient(135deg, #F5F5F5 0%, #E0E0E0 100%);
```

Questa palette è **coerente**, **professionale** e **perfetta** per l'interfaccia di Onepunch-setup! 🎯

