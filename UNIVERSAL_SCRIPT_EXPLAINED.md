# 🌟 Script Universel - Comment ça marche?

## 📝 Vue d'ensemble

Le script `run_universal.sh` **détecte automatiquement** si tu es en mono-site ou multi-site et **adapte son comportement** en conséquence.

## 🔍 La Magie de la Détection

### Étape 1: Compter les sites uniques

```bash
# Créer un dictionnaire (tableau associatif) des sites
declare -A SITES

# Pour chaque nœud dans $OAR_NODEFILE
for hostname in $HOSTNAMES; do
    # Extraire le site (2ème partie du FQDN)
    SITE=$(echo $hostname | cut -d'.' -f2)
    # Ex: dahu-2.grenoble.grid5000.fr → grenoble

    # Compter les nœuds par site
    if [ -z "${SITES[$SITE]}" ]; then
        SITES[$SITE]=1        # Premier nœud de ce site
    else
        SITES[$SITE]=$((${SITES[$SITE]} + 1))  # Incrémenter
    fi
done

# Compter combien de sites différents
SITE_COUNT=${#SITES[@]}
```

### Exemple Concret:

#### Cas 1: Mono-Site
```
$OAR_NODEFILE contient:
dahu-2.grenoble.grid5000.fr
dahu-3.grenoble.grid5000.fr
dahu-4.grenoble.grid5000.fr

Après extraction:
SITES[grenoble] = 3

SITE_COUNT = 1  ← UN SEUL SITE
```

#### Cas 2: Multi-Site
```
$OAR_NODEFILE contient:
dahu-2.grenoble.grid5000.fr
dahu-3.grenoble.grid5000.fr
nova-1.lyon.grid5000.fr
nova-2.lyon.grid5000.fr

Après extraction:
SITES[grenoble] = 2
SITES[lyon] = 2

SITE_COUNT = 2  ← DEUX SITES
```

---

## ⚙️ La Décision Automatique

```bash
if [ $SITE_COUNT -eq 1 ]; then
    MODE="MONO-SITE"
    SLEEP_TIME=5
    echo "✓ Detection: MONO-SITE deployment"
else
    MODE="MULTI-SITE"
    SLEEP_TIME=8
    echo "✓ Detection: MULTI-SITE deployment"
fi
```

**Simple comme bonjour!** Si 1 site = mono, sinon = multi.

---

## 🎨 Adaptation de l'Affichage

### Affichage des Workers

```bash
if [ "$MODE" == "MONO-SITE" ]; then
    # Affichage simple
    echo "👷 Worker nodes:"
    for hostname in $HOSTNAMES; do
        echo "  - $hostname"
    done
else
    # Affichage avec tags de sites
    echo "👷 Worker nodes by site:"
    for hostname in $HOSTNAMES; do
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  [$SITE] $hostname"
    done
fi
```

### Copie des Fichiers

```bash
for hostname in $HOSTNAMES; do
    if [ "$MODE" == "MULTI-SITE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] Copying to $hostname..."
    else
        echo "  - Copying to $hostname..."
    fi

    scp -r bin/ $hostname:~/  # ← MÊME COMMANDE!
done
```

### Sleep Adaptatif

```bash
# Variable définie selon le mode
echo "⏳ Waiting ($SLEEP_TIME seconds)..."
sleep $SLEEP_TIME
#     ↑
#     5 si mono-site, 8 si multi-site
```

### Mesure du Temps (Multi-Site Seulement)

```bash
if [ "$MODE" == "MULTI-SITE" ]; then
    START_TIME=$(date +%s)
fi

java -cp bin scheduler.Main "[$WORKER_LIST]"

if [ "$MODE" == "MULTI-SITE" ]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo "Execution time: ${DURATION}s"
fi
```

---

## 📊 Tableau Comparatif

| Aspect | Comment c'est géré |
|--------|-------------------|
| **Détection** | `SITE_COUNT=${#SITES[@]}` compte les sites uniques |
| **Mode** | `if [ $SITE_COUNT -eq 1 ]` choisit mono ou multi |
| **Affichage** | `if [ "$MODE" == "..." ]` adapte les messages |
| **Sleep** | Variable `$SLEEP_TIME` selon le mode |
| **Timing** | Mesuré uniquement en multi-site |
| **Commandes SCP/SSH** | **IDENTIQUES** dans tous les cas! |

---

## 🚀 Utilisation

### Mono-Site (Automatique)
```bash
# Sur Grenoble
oarsub -I -l nodes=5,walltime=1:00:00
cd ~/wordcount-distributed
./deploy/run_universal.sh

# Output:
# ✓ Detection: MONO-SITE deployment
# All nodes on site: grenoble
```

### Multi-Site (Automatique)
```bash
# Combine nodefiles from Grenoble + Lyon
export OAR_NODEFILE=~/combined_nodefile
./deploy/run_universal.sh

# Output:
# ✓ Detection: MULTI-SITE deployment
# Sites involved: 2
#   ✓ grenoble: 2 node(s) [MASTER]
#   → lyon: 2 node(s)
```

---

## 🔧 Code Clé Expliqué Ligne par Ligne

### Détection des Sites

```bash
# Ligne 1: Créer un dictionnaire vide
declare -A SITES

# Ligne 2: Pour chaque hostname
for hostname in $HOSTNAMES; do

    # Ligne 3: Extraire le nom du site
    SITE=$(echo $hostname | cut -d'.' -f2)
    #           ↑              ↑
    #           |              Coupe sur '.' et prend 2ème champ
    #           hostname = "dahu-2.grenoble.grid5000.fr"
    #
    # Résultat: SITE="grenoble"

    # Ligne 4-9: Compter ou incrémenter
    if [ -z "${SITES[$SITE]}" ]; then
        # Si vide (première fois qu'on voit ce site)
        SITES[$SITE]=1
    else
        # Sinon, incrémenter le compteur
        SITES[$SITE]=$((${SITES[$SITE]} + 1))
    fi
done

# Ligne 10: Compter combien de clés dans le dictionnaire
SITE_COUNT=${#SITES[@]}
#           ↑  ↑
#           |  Nombre d'éléments dans le tableau
#           # opérateur de longueur
```

### Exemple d'exécution:

```bash
# Itération 1: hostname="dahu-2.grenoble.grid5000.fr"
SITE="grenoble"
SITES[grenoble]=1

# Itération 2: hostname="dahu-3.grenoble.grid5000.fr"
SITE="grenoble"
SITES[grenoble]=2  # Incrémenté

# Itération 3: hostname="nova-1.lyon.grid5000.fr"
SITE="lyon"
SITES[lyon]=1

# Résultat final:
SITES[grenoble]=2
SITES[lyon]=1
SITE_COUNT=2  # Deux clés différentes!
```

---

## 💡 Pourquoi c'est Mieux?

### Avantages du Script Universel

| Avantage | Explication |
|----------|-------------|
| **Simplicité** | Un seul script à maintenir au lieu de deux |
| **Automatique** | Pas besoin de choisir, il détecte tout seul |
| **DRY** | Don't Repeat Yourself - pas de code dupliqué |
| **Intelligent** | Adapte le comportement selon le contexte |
| **Robuste** | Fonctionne dans tous les cas |

### Comparaison:

```bash
# Avant (2 scripts):
./deploy/run_mono_site.sh    # Si mono
./deploy/run_multi_site.sh   # Si multi

# Maintenant (1 script):
./deploy/run_universal.sh    # Pour les deux!
```

---

## 🎯 Points Clés à Retenir

1. **Détection par comptage de sites**
   ```bash
   SITE_COUNT=${#SITES[@]}
   if [ $SITE_COUNT -eq 1 ]; then mono; else multi; fi
   ```

2. **Les commandes réelles sont identiques**
   ```bash
   scp -r bin/ $hostname:~/      # Pareil pour mono et multi
   ssh $hostname "java Worker"   # Pareil pour mono et multi
   ```

3. **Seul l'affichage change**
   ```bash
   if [ "$MODE" == "MULTI-SITE" ]; then
       echo "[$SITE] $hostname"  # Avec tag de site
   else
       echo "$hostname"           # Sans tag
   fi
   ```

4. **Sleep adaptatif**
   ```bash
   SLEEP_TIME=5  # Mono
   SLEEP_TIME=8  # Multi
   ```

---

## 🔬 Test du Script

```bash
# Test 1: Mono-site
cd ~/wordcount-distributed
export OAR_NODEFILE=/tmp/mono_nodefile
cat > $OAR_NODEFILE << EOF
dahu-2.grenoble.grid5000.fr
dahu-3.grenoble.grid5000.fr
EOF
./deploy/run_universal.sh
# → Détectera MONO-SITE automatiquement

# Test 2: Multi-site
export OAR_NODEFILE=/tmp/multi_nodefile
cat > $OAR_NODEFILE << EOF
dahu-2.grenoble.grid5000.fr
nova-1.lyon.grid5000.fr
EOF
./deploy/run_universal.sh
# → Détectera MULTI-SITE automatiquement
```

---

## 📚 Résumé

**Le secret:** Un simple `declare -A` pour compter les sites, puis des `if` pour adapter l'affichage!

**Les commandes techniques (scp, ssh, java):** Toujours les mêmes!

**Le résultat:** Un script intelligent qui s'adapte à ton environnement! 🎉
