# 🧪 Guide de Test - Mono-Site et Multi-Site

## 📋 Prérequis

Avant de commencer, assure-toi que:
- ✅ Tu as accès à Grid5000
- ✅ Tu as un compte Grid5000 configuré
- ✅ Tu peux te connecter via SSH

---

## 🔧 Préparation Initiale

### 1. Connexion à Grid5000

```bash
# Depuis ton ordinateur local
ssh <ton-login>@access.grid5000.fr

# Exemple
ssh wailyacoubi@access.grid5000.fr
```

### 2. Choisir un site de départ

```bash
# Connexion à un site (choisis-en un)
ssh grenoble    # ou nancy, lyon, rennes, etc.
```

### 3. Cloner/Mettre à jour le projet

```bash
# Si pas encore cloné
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed

# Si déjà cloné
cd wordcount-distributed
git checkout claude/test-repo-grid-support-01SFCU975DhRRWrpAoX8krpW
git pull origin claude/test-repo-grid-support-01SFCU975DhRRWrpAoX8krpW
```

### 4. Compiler le projet

```bash
# Compiler Java
javac -d bin -sourcepath src $(find src -name '*.java')

# Compiler C
gcc -o wordcount test/wordcount.c

# Vérifier
ls -lh bin/scheduler/Main.class
ls -lh wordcount
```

---

## 🎯 TEST 1: MONO-SITE (Version SCP)

### Étape 1: Réserver des nœuds sur UN SEUL site

```bash
# Réservation interactive (recommandé pour tests)
oarsub -I -l nodes=4,walltime=1:00:00

# Tu verras quelque chose comme:
# [ADMISSION RULE] Modify resource description with type constraints
# OAR_JOB_ID=123456
# Interactive mode: waiting...
# Starting...

# Vérifier les nœuds réservés
cat $OAR_NODEFILE
# dahu-1.grenoble.grid5000.fr
# dahu-1.grenoble.grid5000.fr
# dahu-1.grenoble.grid5000.fr
# dahu-1.grenoble.grid5000.fr
# dahu-2.grenoble.grid5000.fr
# ...
```

### Étape 2: Lancer le test mono-site

```bash
cd ~/wordcount-distributed

# Option A: Script mono-site classique
./deploy/run_mono_site.sh

# Option B: Script universel (détecte auto)
./deploy/run_universal.sh
```

### Étape 3: Observer l'exécution

Tu verras:
```
╔══════════════════════════════════════════════════════════╗
║   MONO-SITE DISTRIBUTED WORD COUNT                      ║
╚══════════════════════════════════════════════════════════╝

📍 Site: grenoble
🖥️  Master node: dahu-1.grenoble.grid5000.fr

👷 Worker nodes:
  - dahu-2.grenoble.grid5000.fr
  - dahu-3.grenoble.grid5000.fr
  - dahu-4.grenoble.grid5000.fr

✅ All nodes confirmed on site: grenoble

📦 Copying files to worker nodes...
  - Copying to dahu-2.grenoble.grid5000.fr...
  - Copying to dahu-3.grenoble.grid5000.fr...
  - Copying to dahu-4.grenoble.grid5000.fr...
✅ Files copied successfully

🚀 Starting worker nodes...
⏳ Waiting for workers to initialize...

╔══════════════════════════════════════════════════════════╗
║   STARTING DISTRIBUTED EXECUTION                        ║
╚══════════════════════════════════════════════════════════╝

[SCHEDULER] Starting task execution...
[TASK count1.txt] ✅ Completed successfully
[TASK count2.txt] ✅ Completed successfully
[TASK count3.txt] ✅ Completed successfully
[TASK count4.txt] ✅ Completed successfully
[TASK count5.txt] ✅ Completed successfully
[TASK total.txt] 📊 Running aggregation locally on master node
[TASK total.txt] ✅ Local execution successful

✅ Execution completed successfully!

📊 RESULTS:
  Total word count: 75000

  Individual counts:
    - part1.txt: 15000 words
    - part2.txt: 15000 words
    - part3.txt: 15000 words
    - part4.txt: 15000 words
    - part5.txt: 15000 words
```

### Étape 4: Vérifier les résultats

```bash
# Voir le total
cat total.txt
# 75000

# Voir les détails
cat count*.txt
# 15000
# 15000
# 15000
# 15000
# 15000

# Vérifier les logs des workers
ls worker.log
```

### Étape 5: Libérer les ressources

```bash
# Le script fait le cleanup automatiquement, mais tu peux vérifier:
exit  # Sortir de la réservation OAR
```

---

## 🌍 TEST 2: MULTI-SITE (Version SCP)

### Méthode A: Avec oargridsub (Recommandé)

```bash
# Sur access.grid5000.fr
ssh access.grid5000.fr

# Réserver sur plusieurs sites en une commande
oargridsub -w 1:00:00 \
  grenoble:rdef="/nodes=2" \
  lyon:rdef="/nodes=2"

# Tu recevras un grid job ID
# Grid job ID: 12345

# Se connecter au site master (premier site)
ssh grenoble

# Ton OAR_NODEFILE contient déjà les nœuds des deux sites
cat $OAR_NODEFILE
# dahu-1.grenoble.grid5000.fr
# dahu-2.grenoble.grid5000.fr
# nova-1.lyon.grid5000.fr
# nova-2.lyon.grid5000.fr

# Lancer le test
cd ~/wordcount-distributed
./deploy/run_multi_site.sh

# OU avec le script universel
./deploy/run_universal.sh
```

### Méthode B: Réservation manuelle (Plus de contrôle)

```bash
# Terminal 1: Site 1 (Grenoble)
ssh access.grid5000.fr
ssh grenoble
oarsub -I -l nodes=2,walltime=1:00:00

# Sauvegarder les nœuds de Grenoble
cat $OAR_NODEFILE > ~/nodefile_grenoble
uniq $OAR_NODEFILE > ~/combined_nodefile

# Garder ce terminal ouvert!
```

```bash
# Terminal 2: Site 2 (Lyon)
ssh access.grid5000.fr
ssh lyon
oarsub -I -l nodes=2,walltime=1:00:00

# Sauvegarder les nœuds de Lyon
cat $OAR_NODEFILE > ~/nodefile_lyon
uniq $OAR_NODEFILE > ~/combined_nodefile_lyon
```

```bash
# Retour au Terminal 1 (Grenoble - Master)

# Récupérer les nœuds de Lyon
MASTER=$(hostname)
scp lyon:~/combined_nodefile_lyon ~/

# Combiner les nodefiles
cat ~/combined_nodefile_lyon >> ~/combined_nodefile

# Vérifier le nodefile combiné
cat ~/combined_nodefile
# dahu-1.grenoble.grid5000.fr
# dahu-2.grenoble.grid5000.fr
# nova-1.lyon.grid5000.fr
# nova-2.lyon.grid5000.fr

# Exporter le nodefile combiné
export OAR_NODEFILE=~/combined_nodefile

# Lancer le test multi-site
cd ~/wordcount-distributed
./deploy/run_multi_site.sh
```

### Observer l'exécution multi-site

```
╔══════════════════════════════════════════════════════════╗
║   MULTI-SITE DISTRIBUTED WORD COUNT                     ║
╚══════════════════════════════════════════════════════════╝

📍 Master site: grenoble
🖥️  Master node: dahu-1.grenoble.grid5000.fr

🗺️  Analyzing site distribution...

Sites involved:
  ✓ grenoble: 2 node(s) [MASTER SITE]
  → lyon: 2 node(s)

✅ Multi-site deployment confirmed (2 sites)

👷 Worker nodes by site:
  [grenoble] dahu-2.grenoble.grid5000.fr
  [lyon] nova-1.lyon.grid5000.fr
  [lyon] nova-2.lyon.grid5000.fr

Total workers: 3 across 2 sites

📡 Multi-site network information:
  - Nodes use fully qualified domain names (FQDN)
  - RMI communication may require specific network configuration
  - Latency between sites: typically 1-10ms depending on sites

📦 Copying files to worker nodes (this may take longer for remote sites)...
  - [grenoble] Copying to dahu-2.grenoble.grid5000.fr...
  - [lyon] Copying to nova-1.lyon.grid5000.fr...
  - [lyon] Copying to nova-2.lyon.grid5000.fr...
✅ Files copied to all sites

🚀 Starting worker nodes across all sites...
⏳ Waiting for workers to initialize across all sites... (8 seconds)

╔══════════════════════════════════════════════════════════╗
║   STARTING MULTI-SITE DISTRIBUTED EXECUTION             ║
╚══════════════════════════════════════════════════════════╝

[SCHEDULER] Starting task execution...
[TASK count1.txt] Assigned to: dahu-2.grenoble.grid5000.fr ✅
[TASK count2.txt] Assigned to: nova-1.lyon.grid5000.fr ✅
[TASK count3.txt] Assigned to: nova-2.lyon.grid5000.fr ✅
[TASK total.txt] 📊 Running aggregation locally on master node
[TASK total.txt] ✅ Local execution successful

✅ Multi-site execution completed successfully!
Execution time: 12s

📊 RESULTS:
  Total word count: 75000

🌐 Multi-site performance:
  Sites involved: 2
  Workers: 3
  Execution time: 12s
```

---

## 🎯 TEST 3: TEST AVEC FICHIER UTILISATEUR

### Test Mono-Site avec Fichier Utilisateur

```bash
# Réserver des nœuds
oarsub -I -l nodes=4,walltime=1:00:00

cd ~/wordcount-distributed

# Créer ton fichier de test
cat > mydata.txt << 'EOF'
Ceci est mon fichier de test personnel.
Grid5000 est une infrastructure de recherche.
Système distribué de comptage de mots.
Java RMI pour la communication.
Makefile pour les dépendances.
EOF

# Lancer avec le script fichier utilisateur
./deploy/run_user_file.sh mydata.txt

# Observer
# Le script va:
# 1. Détecter 3 workers
# 2. Splitter mydata.txt en 3 parts
# 3. Générer Makefile automatiquement
# 4. Exécuter le comptage
# 5. Afficher le résultat
```

### Test Multi-Site avec Fichier Utilisateur

```bash
# Après avoir réservé sur 2+ sites et combiné les nodefiles
export OAR_NODEFILE=~/combined_nodefile

cd ~/wordcount-distributed

# Créer un fichier plus volumineux
cat > large_test.txt << 'EOF'
[Ton texte ici - peut être très long]
EOF

# Lancer
./deploy/run_user_file.sh large_test.txt

# Le système s'adaptera automatiquement au nombre de workers
```

---

## 🧪 TEST 4: VERSION NFS (Optionnel)

### Mono-Site NFS

```bash
oarsub -I -l nodes=4,walltime=1:00:00

cd ~/wordcount-distributed

# Créer fichier test
echo "Test NFS mono-site" > test_nfs.txt

# Lancer
./deploy/run_nfs_mono_site.sh test_nfs.txt
```

### Multi-Site NFS

```bash
# Après combinaison des nodefiles
export OAR_NODEFILE=~/combined_nodefile

./deploy/run_nfs_multi_site.sh ~/combined_nodefile test_nfs.txt
```

---

## ✅ Vérifications Importantes

### 1. Vérifier que les workers ont démarré

```bash
# Sur le master, pendant l'exécution
for host in $(uniq $OAR_NODEFILE | tail -n +2); do
    echo "=== Worker: $host ==="
    ssh $host "ps aux | grep WorkerNode | grep -v grep"
done
```

### 2. Vérifier les logs des workers

```bash
# Sur un worker
ssh dahu-2 "cat ~/worker.log"
```

### 3. Vérifier la communication RMI

```bash
# Sur le master
netstat -an | grep 3000  # Port RMI par défaut
```

### 4. Vérifier les fichiers transférés

```bash
# Sur un worker
ssh dahu-2 "ls -lh ~/"
# Devrait voir: bin/, wordcount, part*.txt, Makefile
```

---

## 🔍 Troubleshooting

### Problème: "OAR_NODEFILE not found"
```bash
# Solution: Vérifier que tu es dans une réservation OAR
echo $OAR_NODEFILE
# Si vide, tu n'es pas dans une réservation
oarsub -I -l nodes=4,walltime=1:00:00
```

### Problème: "Failed to copy files to worker"
```bash
# Vérifier la connectivité SSH
ssh dahu-2 "hostname"

# Vérifier les clés SSH
ssh-copy-id dahu-2
```

### Problème: "All workers busy, waiting..."
```bash
# Les workers ne répondent pas
# Vérifier qu'ils tournent:
for host in $(uniq $OAR_NODEFILE | tail -n +2); do
    ssh $host "ps aux | grep WorkerNode"
done

# Si aucun worker, les redémarrer manuellement
```

### Problème: Résultat incorrect (ex: 43041 au lieu de 75000)
```bash
# Vérifier que c'est bien la version avec le fix d'agrégation
grep "Running aggregation locally" total.txt

# Vérifier que tous les count*.txt existent
ls -lh count*.txt

# Vérifier le contenu
cat count*.txt
```

---

## 📊 Résultats Attendus

### Mono-Site (5 workers):
```
Total: 75000 mots
count1.txt: 15000
count2.txt: 15000
count3.txt: 15000
count4.txt: 15000
count5.txt: 15000
```

### Multi-Site (Grenoble + Lyon):
```
Total: 75000 mots
Distribution des tâches entre les deux sites
Temps d'exécution: légèrement plus long (quelques secondes)
```

### Fichier Utilisateur:
```
Total: dépend de ton fichier
Nombre de parts = nombre de workers
Division équitable (±1 ligne)
```

---

## 🎯 Checklist de Test Complète

### Phase 1: Préparation
- [ ] Connexion à Grid5000
- [ ] Projet cloné et à jour
- [ ] Code compilé (Java + C)

### Phase 2: Mono-Site
- [ ] Réservation réussie (oarsub)
- [ ] Script lancé (run_mono_site.sh)
- [ ] Workers démarrés
- [ ] Exécution complète
- [ ] Résultat correct (75000)

### Phase 3: Multi-Site
- [ ] Réservation sur 2+ sites
- [ ] Nodefiles combinés
- [ ] Script lancé (run_multi_site.sh)
- [ ] Workers sur plusieurs sites
- [ ] Communication inter-sites OK
- [ ] Résultat correct (75000)

### Phase 4: Fichier Utilisateur
- [ ] Fichier créé
- [ ] run_user_file.sh lancé
- [ ] Makefile généré automatiquement
- [ ] Split équitable
- [ ] Résultat correct

### Phase 5: Version NFS (Optionnel)
- [ ] NFS configuré
- [ ] run_nfs_mono_site.sh testé
- [ ] run_nfs_multi_site.sh testé
- [ ] Résultats identiques à SCP

---

## 🚀 Commandes Rapides (Résumé)

```bash
# MONO-SITE
ssh grenoble.grid5000.fr
oarsub -I -l nodes=4,walltime=1:00:00
cd ~/wordcount-distributed
./deploy/run_mono_site.sh

# MULTI-SITE
oargridsub -w 1:00:00 grenoble:rdef="/nodes=2" lyon:rdef="/nodes=2"
ssh grenoble
cd ~/wordcount-distributed
./deploy/run_multi_site.sh

# FICHIER UTILISATEUR
echo "Mon texte" > myfile.txt
./deploy/run_user_file.sh myfile.txt

# UNIVERSEL (détecte auto)
./deploy/run_universal.sh
```

---

## 📚 Documentation Supplémentaire

- Grid5000: https://www.grid5000.fr/
- OAR: https://oar.imag.fr/
- README.md du projet
- NFS_USAGE.md (pour version NFS)
- UNIVERSAL_SCRIPT_EXPLAINED.md (pour script universel)

Bon tests! 🎉
