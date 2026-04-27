# MCU2026-GXXX – Jeu Dino interactif sur ATmega128

**Auteurs :** Sibrecht van Hovell – Victor Miclea
**Cours :** EE208 – Microcontrôleurs et systèmes numériques  
**Groupe :** 16  

---

## 1. Introduction et description générale

Ce projet a pour objectif de développer un **jeu interactif type “Dino”** sur le microcontrôleur ATmega128 avec la carte STK300. Le joueur contrôle un personnage qui saute pour éviter des obstacles.  

**Fonctionnalités principales :**
- Saut contrôlé par **mouvement de main** devant le capteur de distance Sharp GP2Y0A21  
- Menu interactif géré via **télécommande IR RC5**  
- Affichage des scores et menus sur **LCD 2x16**  
- Musique et effets sonores via **buzzer piezo**  
- Système de **vies et difficultés** (LED sur STK300)  
- Enregistrement et affichage des **5 meilleurs scores**  

---

## 2. Interface utilisateur et menu

### 2.1 Menu principal
- **1 → Start Game** : commence la partie  
- **2 → Select Difficulty** : choisit le mode (Facile = 3 vies, Normal = 2 vies, Difficile = 1 vie)  
- **3 → High Scores** : affiche les 5 derniers meilleurs scores sur le LCD  
- **0 → Quit** : quitte le jeu  

### 2.2 Contrôles
- **Saut du Dino** : geste de main devant le capteur de distance  
- **Pause / Reprise** : bouton `1` de la télécommande IR  
- **Retour menu** : bouton `0` de la télécommande IR  

---

## 3. Architecture logicielle

### 3.1 Modules principaux
| Module | Périphérique | Fonction |
|--------|--------------|---------|
| IR RC5 | Télécommande IR | Navigation menu, pause, retour menu |
| Capteur distance | Sharp GP2Y0A21 | Détection geste pour saut |
| LCD | LCD 2x16 | Affichage score, menus, High Scores |
| LED | LEDs STK300 | Affichage vies restantes |
| Buzzer | Buzzer piezo | Sons et musique |
| Game Logic / Timer | Timer interne | Déplacement obstacles, score, collisions |

### 3.2 Variables clés
```text
difficulty_mode: 0=Facile,1=Normal,2=Difficile
lives: vies restantes
current_score: score actuel
high_scores[5]: tableau des 5 meilleurs scores
game_state: MENU, RUNNING, PAUSED, GAME_OVER
dino_state: SOL, SAUT
obstacles[]: positions des obstacles
