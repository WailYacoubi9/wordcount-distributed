# Guide Complet: Implémentation NFS sur Grid5000

## 🎯 Objectif

Configurer un **vrai système NFS** (Network File System) pour le projet de comptage de mots distribué, avec serveur NFS sur le master et clients NFS sur les workers.

---

## 📋 Prérequis

### 1. Comprendre NFS

**NFS (Network File System)** est un protocole qui permet de:
- Partager des répertoires entre machines via le réseau
- Monter un répertoire distant comme s'il était local
- Accéder aux fichiers de manière transparente

**Architecture:**
```
Serveur NFS (Master)              Client NFS (Worker)
├─ /tmp/nfs_shared (local)       ├─ /tmp/nfs_shared (monté)
│  └─ part1.txt                  │  └─ part1.txt (même fichier!)
│                                │
└─ nfs-kernel-server             └─ nfs-common
   (exportation)                    (montage)
```

### 2. Besoin de Sudo

**Pourquoi sudo est nécessaire:**
- Éditer `/etc/exports` (configuration système)
- Démarrer le service `nfs-server` (service système)
- Monter un filesystem avec `mount` (opération privilégiée)

**Sur Grid5000:**
- ❌ Pas de sudo par défaut
- ✅ Sudo disponible après `kadeploy`

---

## 🚀 Méthode 1: Utiliser Kadeploy (Recommandé)

### Étape 1: Réserver des Nœuds

**Depuis le frontend Grid5000 (ex: fgrenoble.grid5000.fr):**

```bash
# Connexion au frontend
ssh wyacoubi@access.grid5000.fr
ssh grenoble

# Réserver 4 nœuds pour 1 heure
oarsub -I -l nodes=4,walltime=1:00:00
```

**Résultat:**
```
OAR_JOB_ID=2583838
Reservation OK
Interactive mode: waiting...
Starting...
Connect to OAR job 2583838 via the node dahu-15.grenoble.grid5000.fr
```

### Étape 2: Redéployer avec Kadeploy

**Depuis la session OAR interactive:**

```bash
# Vérifier les nœuds réservés
cat $OAR_NODEFILE
# dahu-15.grenoble.grid5000.fr
# dahu-3.grenoble.grid5000.fr
# dahu-30.grenoble.grid5000.fr
# dahu-31.grenoble.grid5000.fr

# Redéployer avec Debian 11 (avec clé SSH)
kadeploy3 -f $OAR_NODEFILE -e debian11-x64-std -k
```

**Sortie attendue:**
```
Deploying debian11-x64-std on 4 nodes...
[████████████████████████████████] 100%
Deployment successful on 4 nodes
```

**Attendre ~5-10 minutes** pour le déploiement complet.

### Étape 3: Vérifier les Privilèges Root

```bash
# Tester sudo
sudo whoami
# Devrait afficher: root

# Se reconnecter si nécessaire
ssh dahu-15
```

### Étape 4: Installer NFS

**Sur TOUS les nœuds (master + workers):**

```bash
# Se connecter au master
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)

# Installer NFS sur le master
ssh $MASTER "sudo apt-get update && sudo apt-get install -y nfs-kernel-server nfs-common"

# Installer NFS sur les workers
for worker in $WORKERS; do
    echo "Installing NFS on $worker..."
    ssh $worker "sudo apt-get update && sudo apt-get install -y nfs-common" &
done
wait

echo "✅ NFS installed on all nodes"
```

### Étape 5: Configurer le Serveur NFS (Master)

**Sur le master:**

```bash
# 1. Créer le répertoire partagé
ssh $MASTER "sudo mkdir -p /tmp/nfs_shared"
ssh $MASTER "sudo chmod 777 /tmp/nfs_shared"

# 2. Configurer /etc/exports
ssh $MASTER "echo '/tmp/nfs_shared *(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports"

# 3. Exporter le répertoire
ssh $MASTER "sudo exportfs -ra"

# 4. Démarrer le serveur NFS
ssh $MASTER "sudo systemctl restart nfs-server"
ssh $MASTER "sudo systemctl enable nfs-server"

# 5. Vérifier que le serveur fonctionne
ssh $MASTER "sudo systemctl status nfs-server | head -5"
ssh $MASTER "sudo exportfs -v"
```

**Sortie attendue:**
```
/tmp/nfs_shared
        *(rw,wdelay,root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash)
```

### Étape 6: Monter NFS sur les Workers

**Sur chaque worker:**

```bash
for worker in $WORKERS; do
    echo "Mounting NFS on $worker..."
    # Créer le point de montage
    ssh $worker "sudo mkdir -p /tmp/nfs_shared"

    # Monter le filesystem NFS
    ssh $worker "sudo mount -t nfs ${MASTER}:/tmp/nfs_shared /tmp/nfs_shared"

    # Vérifier le montage
    ssh $worker "df -h /tmp/nfs_shared"
done

echo "✅ NFS mounted on all workers"
```

**Sortie attendue:**
```
Filesystem                          Size  Used Avail Use% Mounted on
dahu-15:/tmp/nfs_shared              50G  1.0G   46G   2% /tmp/nfs_shared
```

### Étape 7: Tester le Partage NFS

**Vérifier que le partage fonctionne:**

```bash
# Créer un fichier sur le master
ssh $MASTER "echo 'Test NFS' > /tmp/nfs_shared/test.txt"

# Vérifier qu'il est visible sur un worker
ssh $(echo $WORKERS | head -n 1) "cat /tmp/nfs_shared/test.txt"
# Devrait afficher: Test NFS

echo "✅ NFS sharing works!"
```

### Étape 8: Cloner et Compiler le Projet

```bash
# Sur le master
ssh $MASTER "cd ~ && git clone https://github.com/WailYacoubi9/wordcount-distributed.git"
ssh $MASTER "cd ~/wordcount-distributed && javac -d bin src/**/*.java"

# Créer un fichier de test
ssh $MASTER "cd ~/wordcount-distributed && for i in {1..1000}; do echo 'ligne de test numero \$i avec plusieurs mots'; done > bigtest.txt"
```

### Étape 9: Exécuter avec NFS

```bash
# Lancer le script NFS
ssh $MASTER "cd ~/wordcount-distributed && bash deploy/run_nfs_mono_site.sh bigtest.txt"
```

**Résultat attendu:**
```
╔══════════════════════════════════════════════════════════╗
║   NFS Mono-Site Distributed Word Count                 ║
╚══════════════════════════════════════════════════════════╝

📁 Setting up NFS shared directory...
✅ NFS directory created: /tmp/nfs_shared
📤 Configuring NFS export...
✅ NFS exported successfully
🔗 Mounting NFS on workers...
✅ NFS mounted on all workers

🚀 Starting distributed execution (NFS mode)...
[CLUSTER] Master node: dahu-15.grenoble.grid5000.fr (coordination only)
[CLUSTER] Worker nodes: 3
[CLUSTER]   - dahu-3.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-30.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-31.grenoble.grid5000.fr:3000

[SPLITTER] Total lines in input: 1000
[SPLITTER] Base lines per worker: 333
[SPLITTER] Workers with extra line: 1

✅ Execution completed!

╔════════════════════════════╗
║  Total word count: 8000     ║
╚════════════════════════════╝
```

---

## 🛠️ Méthode 2: Sans Kadeploy (Limitations)

### Option A: Utiliser /home (Astuce Grid5000)

**Si /home est déjà sur NFS:**

```bash
bash deploy/run_nfs_home.sh bigtest.txt
```

**Avantages:**
- ✅ Fonctionne immédiatement
- ✅ Pas besoin de sudo

**Inconvénients:**
- ❌ Ce n'est PAS du vrai NFS (pas de configuration)
- ⚠️ Académiquement moins valable

### Option B: SSHFS (Alternative sans sudo)

**SSHFS = Filesystem via SSH (pas NFS, mais similaire):**

```bash
# Installer sshfs (si disponible)
apt-get install sshfs  # Si pas root, demander à l'admin

# Monter via SSHFS (pas besoin sudo avec fuse)
mkdir -p ~/sshfs_shared
sshfs $MASTER:/tmp/nfs_shared ~/sshfs_shared
```

**Limitation:** SSHFS n'est pas NFS, c'est une alternative.

---

## 🔍 Comprendre le Protocole NFS

### 1. Le Fichier /etc/exports

**Syntaxe:**
```bash
/tmp/nfs_shared *(rw,sync,no_subtree_check,no_root_squash)
│               │ │                          │
│               │ │                          └─ Autoriser root distant
│               │ └─ Synchronisation immédiate
│               └─ Wildcard: tous les clients autorisés
└─ Répertoire à partager
```

**Options importantes:**
- `rw` = Read-Write (lecture/écriture)
- `ro` = Read-Only (lecture seule)
- `sync` = Synchronisation immédiate (pas de cache)
- `async` = Cache autorisé (plus rapide mais moins sûr)
- `no_root_squash` = Root distant a les mêmes droits
- `root_squash` = Root distant devient nobody (sécurité)

### 2. La Commande mount

**Syntaxe:**
```bash
mount -t nfs serveur:/chemin/distant /point/montage/local
│     │      │                       │
│     │      │                       └─ Où monter localement
│     │      └─ Serveur et chemin distant
│     └─ Type de filesystem (nfs)
└─ Commande mount
```

**Exemple:**
```bash
mount -t nfs dahu-15:/tmp/nfs_shared /tmp/nfs_shared
# Après: /tmp/nfs_shared sur dahu-3 pointe vers dahu-15:/tmp/nfs_shared
```

### 3. Les Services NFS

**Sur le serveur (master):**
```bash
systemctl start nfs-server      # Démarrer
systemctl enable nfs-server     # Activer au boot
systemctl status nfs-server     # Vérifier statut
```

**Sur le client (worker):**
```bash
# Pas de service à démarrer, juste monter
mount -t nfs server:/path /local/path
```

---

## 📊 Vérifications et Debugging

### Vérifier que NFS fonctionne

**Sur le serveur:**
```bash
# Vérifier les exports
sudo exportfs -v

# Vérifier que le service tourne
sudo systemctl status nfs-server

# Vérifier les connexions
sudo netstat -tuln | grep 2049  # Port NFS
```

**Sur le client:**
```bash
# Vérifier les montages
df -h | grep nfs
mount | grep nfs

# Tester l'accès
ls -la /tmp/nfs_shared
echo "test" > /tmp/nfs_shared/test.txt
```

### Problèmes Courants

**1. Permission denied**
```bash
# Solution: Vérifier les permissions
sudo chmod 777 /tmp/nfs_shared
```

**2. Mount failed: Connection refused**
```bash
# Solution: Vérifier que le serveur NFS tourne
sudo systemctl restart nfs-server
```

**3. Stale file handle**
```bash
# Solution: Remonter le filesystem
sudo umount /tmp/nfs_shared
sudo mount -t nfs server:/tmp/nfs_shared /tmp/nfs_shared
```

---

## 🎓 Pour le Rendu Académique

### Présentation au Prof

**Structure recommandée:**

1. **Introduction**
   - "J'ai implémenté un système distribué de comptage de mots avec deux architectures"

2. **Mode SCP (Principal)**
   - Architecture avec stockage indépendant
   - Transferts explicites via SCP
   - Démonstration

3. **Mode NFS (Avancé)**
   - Configuration complète d'un serveur NFS
   - Export et montage de filesystems
   - Utilisation de kadeploy pour obtenir les privilèges root
   - Démonstration

4. **Comparaison**
   - Avantages/inconvénients de chaque approche
   - Cas d'usage

### Documentation à Fournir

**README.md avec:**
```markdown
# Modes d'Exécution

## Mode SCP (Standard)
- Chaque nœud a son propre stockage
- Transferts via SCP
- Commande: `bash deploy/run_scp.sh input.txt`

## Mode NFS (Avancé - Nécessite sudo)
- Filesystem partagé via NFS
- Nécessite kadeploy pour sudo
- Commande: `bash deploy/run_nfs_mono_site.sh input.txt`

### Configuration NFS
1. Redéployer avec kadeploy: `kadeploy3 -f $OAR_NODEFILE -e debian11-x64-std -k`
2. Installer NFS: `apt-get install nfs-kernel-server nfs-common`
3. Configurer serveur et clients (voir NFS_COMPLETE_GUIDE.md)
```

---

## 📚 Ressources

**Documentation officielle:**
- [Grid5000 - Kadeploy](https://www.grid5000.fr/w/Kadeploy)
- [Grid5000 - Advanced Deployment](https://www.grid5000.fr/w/Advanced_OAR)
- [NFS Server Configuration](https://ubuntu.com/server/docs/service-nfs)

**Commandes utiles:**
```bash
# Lister les environnements kadeploy disponibles
kaenv3 -l

# Vérifier le statut d'un déploiement
kadeploy3 -s

# Démonter NFS
sudo umount /tmp/nfs_shared

# Réexporter NFS après modification de /etc/exports
sudo exportfs -ra
```

---

## ✅ Checklist Finale

**Avant de présenter:**

- [ ] Tester mode SCP sans NFS
- [ ] Faire un kadeploy complet
- [ ] Installer et configurer NFS
- [ ] Tester mode NFS avec vrai serveur
- [ ] Vérifier que les résultats sont identiques
- [ ] Préparer slides expliquant les deux architectures
- [ ] Documenter les commandes dans le README

---

## 🎯 Conclusion

**Tu as maintenant:**
- ✅ Compréhension complète du protocole NFS
- ✅ Méthode pour utiliser kadeploy
- ✅ Configuration serveur/client NFS
- ✅ Deux modes fonctionnels (SCP + NFS)
- ✅ Documentation complète pour le rendu

**Bon courage pour ton projet!** 🚀
