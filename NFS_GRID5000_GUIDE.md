# 🌐 Guide d'Exécution NFS Mono-Site sur Grid5000

## 📋 Contenu du Repo - Version NFS

Le repo contient deux implémentations parallèles:

### Version SCP (Sans sudo)
- `deploy/run_mono_site.sh`
- `deploy/run_multi_site.sh`
- `deploy/run_user_file.sh`

### Version NFS (Requiert sudo OU kadeploy)
- `deploy/run_nfs_mono_site.sh` ✅ Tu vas utiliser celui-ci
- `deploy/run_nfs_multi_site.sh`

## ⚠️ Problème: NFS nécessite sudo

Le script NFS utilise ces commandes qui nécessitent les droits root:
```bash
sudo tee -a /etc/exports              # Ligne 72
sudo exportfs -ra                     # Ligne 73
sudo systemctl restart nfs-server     # Ligne 74
sudo mount -t nfs ...                 # Ligne 80
```

## 🎯 Solution: Deux Approches

---

## ✅ APPROCHE 1: Kadeploy (Recommandé pour NFS Réel)

Kadeploy déploie un système d'exploitation complet où tu as les droits sudo.

### Étape 1: Réserver des nœuds

```bash
# Connexion à Grid5000
ssh <ton-login>@access.grid5000.fr
ssh grenoble  # ou nancy, lyon, etc.

# Réserver 4 nœuds pour 1 heure
oarsub -I -l nodes=4,walltime=1:00:00
```

Tu verras:
```
[ADMISSION RULE] Modify resource description with type constraints
OAR_JOB_ID=123456
Interactive mode: waiting...
Starting...
```

### Étape 2: Déployer un environnement avec kadeploy

```bash
# Voir les environnements disponibles
kaenv3 -l | grep debian

# Déployer Debian (avec NFS support)
kadeploy3 -f $OAR_NODEFILE -e debian11-x64-nfs -k

# OU environnement standard
kadeploy3 -f $OAR_NODEFILE -e debian11-x64-std -k
```

**Attendre 5-10 minutes** pour le déploiement.

Tu verras:
```
Deploying debian11-x64-nfs on 4 nodes
[===================] 100% (4/4)
Deployment successful!
```

### Étape 3: Se reconnecter aux nœuds

```bash
# Les nœuds ont redémarré, tu dois te reconnecter
MASTER=$(head -n 1 $OAR_NODEFILE)
ssh root@$MASTER

# Maintenant tu es root! Tu peux utiliser sudo
```

### Étape 4: Installer les dépendances NFS

```bash
# Sur le master (en tant que root)
apt-get update
apt-get install -y nfs-kernel-server nfs-common

# Sur chaque worker
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)
for worker in $WORKERS; do
    ssh root@$worker "apt-get update && apt-get install -y nfs-common"
done
```

### Étape 5: Cloner et préparer le projet

```bash
# Sur le master (toujours en root)
cd /root
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed
git checkout claude/test-repo-grid-support-01SFCU975DhRRWrpAoX8krpW

# Compiler
apt-get install -y default-jdk gcc
javac -d bin -sourcepath src $(find src -name '*.java')
gcc -o wordcount test/wordcount.c
```

### Étape 6: Créer ton fichier de test

```bash
# Créer un fichier test
cat > test_nfs.txt << 'EOF'
Test NFS mono-site sur Grid5000.
Système distribué de comptage de mots.
Java RMI communication entre nœuds.
Grenoble infrastructure de recherche.
Makefile parsing et exécution.
Architecture distribuée multi-workers.
EOF
```

### Étape 7: Lancer le test NFS

```bash
# Exécuter le script NFS
./deploy/run_nfs_mono_site.sh test_nfs.txt
```

Tu verras:
```
╔══════════════════════════════════════════════════════════╗
║     DISTRIBUTED WORD COUNT - NFS Mono-Site Setup       ║
╚══════════════════════════════════════════════════════════╝

🖥️  Master node: dahu-1.grenoble.grid5000.fr
👷 Workers (3):
     1  dahu-2.grenoble.grid5000.fr
     2  dahu-3.grenoble.grid5000.fr
     3  dahu-4.grenoble.grid5000.fr

📁 Setting up NFS shared directory...
✅ NFS directory created: /tmp/nfs_shared

📤 Configuring NFS export...
✅ NFS exported

🔗 Mounting NFS on workers...
  Mounting on dahu-2.grenoble.grid5000.fr...
  Mounting on dahu-3.grenoble.grid5000.fr...
  Mounting on dahu-4.grenoble.grid5000.fr...
✅ NFS mounted on all workers

📦 Deploying workers...
🚀 Starting worker nodes...
⏳ Waiting for workers to initialize...

[MAIN-NFS] 🔄 Dynamic mode: Auto-generating Makefile from input file
[SPLITTER] Splitting file into 3 parts...
[MAIN-NFS] ✅ Files available in shared NFS directory

[SCHEDULER-NFS] Starting task execution...
[TASK-NFS count1.txt] ✅ Completed successfully
[TASK-NFS count2.txt] ✅ Completed successfully
[TASK-NFS count3.txt] ✅ Completed successfully
[TASK-NFS total.txt] 📊 Running aggregation locally

✅ Execution completed!

╔════════════════════════════════════╗
║  Total word count: 36              ║
╚════════════════════════════════════╝
```

### Étape 8: Vérifier les résultats

```bash
# Voir le résultat final
cat /tmp/nfs_shared/total.txt
# 36

# Voir les fichiers créés dans le répertoire NFS
ls -lh /tmp/nfs_shared/
# part1.txt  part2.txt  part3.txt
# count1.txt count2.txt count3.txt
# total.txt  Makefile.generated

# Vérifier sur un worker que NFS est monté
ssh dahu-2 "ls -lh /tmp/nfs_shared/"
# Même contenu! C'est le répertoire partagé
```

---

## 💡 APPROCHE 2: Version Simplifiée (Sans sudo, sans kadeploy)

Si kadeploy est trop complexe, voici une version simplifiée qui n'utilise pas NFS réel mais simule le comportement:

### Version Alternative sans NFS

Je vais créer un script modifié qui fonctionne sans sudo:

```bash
cd ~/wordcount-distributed

# Créer un script simplifié
cat > deploy/run_nfs_simple.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

NFS_SHARED_DIR="$HOME/shared_wordcount"
PORT=3000

# Créer répertoire partagé sur master
mkdir -p $NFS_SHARED_DIR

# Get workers
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)

# "Simuler" NFS en copiant le répertoire sur tous les workers
echo "Setting up shared directory on all nodes..."
for worker in $WORKERS; do
    ssh $worker "mkdir -p $NFS_SHARED_DIR"
done

# Copier les fichiers de test
cp -r test/ $NFS_SHARED_DIR/
cp "$1" $NFS_SHARED_DIR/ 2>/dev/null || true

# Compiler wordcount dans le répertoire partagé
gcc -o $NFS_SHARED_DIR/wordcount test/wordcount.c

# Sync vers workers
for worker in $WORKERS; do
    scp -r $NFS_SHARED_DIR/* $worker:$NFS_SHARED_DIR/
done

# Démarrer workers
for worker in $WORKERS; do
    scp -r bin/ $worker:~/
    ssh $worker "nohup java -cp ~/bin network.worker.WorkerNode $worker $PORT > worker.log 2>&1 &" &
done

sleep 5

# Build worker list
WORKER_LIST="["
FIRST=true
for worker in $WORKERS; do
    if [ "$FIRST" = true ]; then
        WORKER_LIST="${WORKER_LIST}${worker}:${PORT}"
        FIRST=false
    else
        WORKER_LIST="${WORKER_LIST},${worker}:${PORT}"
    fi
done
WORKER_LIST="${WORKER_LIST}]"

# Run with MainNFS
INPUT_FILE=$(basename "$1")
java -cp bin scheduler.MainNFS "$NFS_SHARED_DIR/$INPUT_FILE" "$WORKER_LIST" "$NFS_SHARED_DIR"

# Récupérer résultats des workers
for worker in $WORKERS; do
    scp $worker:$NFS_SHARED_DIR/count*.txt $NFS_SHARED_DIR/ 2>/dev/null || true
done

# Afficher résultat
cat $NFS_SHARED_DIR/total.txt

# Cleanup
for worker in $WORKERS; do
    ssh $worker "pkill -f WorkerNode" 2>/dev/null || true
done
SCRIPT_EOF

chmod +x deploy/run_nfs_simple.sh
```

### Utiliser la version simplifiée:

```bash
# Réserver des nœuds (sans kadeploy)
oarsub -I -l nodes=4,walltime=1:00:00

# Créer fichier test
echo "Test simplifié NFS" > mytest.txt

# Lancer
./deploy/run_nfs_simple.sh mytest.txt
```

---

## 📊 Comparaison des Approches

| Approche | Avantages | Inconvénients | Recommandé? |
|----------|-----------|---------------|-------------|
| **Kadeploy + NFS réel** | NFS authentique, sudo disponible | Complexe, déploiement long (10min) | ✅ Pour tester vraiment NFS |
| **Version simplifiée** | Simple, pas de sudo | Pas de vrai NFS, sync manuel | ⚠️ Simulation uniquement |
| **Version SCP** | Simple, fonctionne partout | Pas NFS | ✅ Pour projet final |

---

## 🎯 Recommandation Finale

### Pour TESTER NFS Mono-Site:

**Utilise Approche 1 (Kadeploy)** une fois pour voir comment NFS fonctionne:

```bash
# 1. Réserver
oarsub -I -l nodes=4,walltime=1:00:00

# 2. Déployer
kadeploy3 -f $OAR_NODEFILE -e debian11-x64-std -k

# 3. Se connecter en root
ssh root@$(head -n 1 $OAR_NODEFILE)

# 4. Installer et tester
apt-get update && apt-get install -y nfs-kernel-server default-jdk gcc git
cd /root
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed
git checkout claude/test-repo-grid-support-01SFCU975DhRRWrpAoX8krpW
javac -d bin -sourcepath src $(find src -name '*.java')
gcc -o wordcount test/wordcount.c

# 5. Lancer NFS
echo "Test NFS Grid5000" > test.txt
./deploy/run_nfs_mono_site.sh test.txt
```

### Pour TON PROJET (Tests réguliers):

**Utilise la version SCP** (pas besoin de sudo, plus simple):

```bash
oarsub -I -l nodes=4,walltime=1:00:00
cd ~/wordcount-distributed
./deploy/run_universal.sh
```

---

## ✅ Résumé

**NFS mono-site nécessite:**
1. Environnement kadeploy (pour avoir sudo)
2. Installation NFS server/client
3. Configuration exports/mounts
4. Puis lancer `run_nfs_mono_site.sh`

**OU utilise la version SCP** qui fonctionne immédiatement sans configuration! 🚀
