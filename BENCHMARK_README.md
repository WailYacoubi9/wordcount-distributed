# Système de Benchmarking : NFS vs SCP

## 📊 Vue d'ensemble

Ce système permet de comparer les performances de deux méthodes de transfert de fichiers dans un environnement distribué :
- **NFS** (Network File System) : Système de fichiers partagé
- **SCP** (Secure Copy Protocol) : Transfert explicite de fichiers

## ⚠️ Note importante : Pas besoin de sudo !

Ce système de benchmarking **NE NÉCESSITE PAS** de privilèges sudo. Tout fonctionne avec des permissions utilisateur normales, ce qui le rend compatible avec Grid5000 et autres environnements restreints.

## 🚀 Utilisation rapide

### 1. Compilation

```bash
# Compiler le projet avec les nouvelles classes
cd /home/user/wordcount-distributed
mkdir -p bin
find src -name "*.java" > sources.txt
javac -d bin -sourcepath src @sources.txt
```

### 2. Exécution manuelle d'un benchmark

#### Test avec SCP
```bash
java -cp bin scheduler.Main "[localhost]" --method=SCP --benchmark --output-dir=benchmarks/scp
```

#### Test avec NFS
```bash
java -cp bin scheduler.Main "[localhost]" --method=NFS --benchmark --output-dir=benchmarks/nfs
```

### 3. Exécution automatisée (plusieurs runs)

```bash
chmod +x scripts/run_benchmarks.sh
./scripts/run_benchmarks.sh --workers "[localhost]" --runs 5
```

## 📝 Options disponibles

### Programme principal (Main.java)

```bash
java -cp bin scheduler.Main "<workers>" [OPTIONS]

Arguments:
  <workers>              Liste des workers : "[host1,host2,...]"

Options:
  --method=<SCP|NFS>     Méthode de transfert (défaut: SCP)
  --benchmark            Active le benchmarking
  --output-dir=<dir>     Répertoire de sortie (défaut: benchmarks)
```

### Script de benchmark automatique

```bash
./scripts/run_benchmarks.sh [OPTIONS]

Options:
  --workers <list>       Liste des workers (défaut: [localhost])
  --runs <number>        Nombre d'exécutions par méthode (défaut: 3)
  --output <dir>         Répertoire de sortie (défaut: benchmarks)
  --no-compile           Sauter la compilation
  --help                 Afficher l'aide
```

## 📈 Génération des graphes

### Dépendances Python

```bash
# Installer les dépendances (si pas déjà installé)
pip3 install pandas matplotlib seaborn
```

### Générer les graphes

```bash
python3 scripts/generate_benchmark_graphs.py benchmarks/
```

### Graphes générés

Le script génère automatiquement :

1. **comparison_by_operation.png** : Comparaison par type d'opération
2. **file_transfer_comparison.png** : Distribution des temps de transfert
3. **execution_timeline.png** : Timeline d'exécution
4. **total_execution_time.png** : Temps d'exécution total
5. **summary_table.png** : Tableau statistique
6. **benchmark_report.txt** : Rapport textuel détaillé

## 📂 Structure des résultats

```
benchmarks/
├── scp/
│   ├── benchmark_scp_<timestamp>.csv    # Données brutes
│   ├── summary_scp_<timestamp>.csv      # Statistiques résumées
│   └── run_*.log                        # Logs d'exécution
├── nfs/
│   ├── benchmark_nfs_<timestamp>.csv
│   ├── summary_nfs_<timestamp>.csv
│   └── run_*.log
└── graphs/
    ├── comparison_by_operation.png
    ├── file_transfer_comparison.png
    ├── execution_timeline.png
    ├── total_execution_time.png
    ├── summary_table.png
    └── benchmark_report.txt
```

## 🔧 Configuration NFS

Pour utiliser NFS, vous devez configurer un répertoire partagé :

```bash
# Par défaut : /tmp/wordcount_shared
# Vous pouvez le changer dans Configuration.java

# Créer le répertoire partagé (pas besoin de sudo !)
mkdir -p /tmp/wordcount_shared
```

**Note** : Sur Grid5000, utilisez un chemin dans votre home ou un espace temporaire accessible :

```bash
mkdir -p $HOME/wordcount_shared
# Puis modifiez Configuration.java : setNfsSharedPath("$HOME/wordcount_shared")
```

## 📊 Format des données CSV

### benchmark_*.csv
```
transfer_method,task_name,operation,duration_ms,timestamp,filename,file_size
SCP,count1.txt,file_transfer,150,1234567890,count1.txt,2048
SCP,count1.txt,command_execution,450,1234567891,,0
```

### summary_*.csv
```
transfer_method,operation,count,total_ms,avg_ms,min_ms,max_ms
SCP,file_transfer,5,750,150.00,120,180
SCP,command_execution,5,2250,450.00,400,500
```

## 🎯 Exemple complet sur Grid5000

```bash
# 1. Se connecter à Grid5000
ssh nancy.grid5000.fr

# 2. Réserver des nœuds
oarsub -I -l nodes=3,walltime=1:00:00

# 3. Préparer l'environnement
cd /home/$USER/wordcount-distributed
mkdir -p bin benchmarks

# 4. Compiler
find src -name "*.java" > sources.txt
javac -d bin -sourcepath src @sources.txt

# 5. Lancer les workers sur chaque nœud
# (sur chaque worker)
java -cp bin network.worker.WorkerService &

# 6. Lancer le benchmark depuis le master
NODES=$(uniq $OAR_NODE_FILE | paste -sd,)
./scripts/run_benchmarks.sh --workers "[$NODES]" --runs 5

# 7. Générer les graphes
module load python/3.8
pip3 install --user pandas matplotlib seaborn
python3 scripts/generate_benchmark_graphs.py benchmarks/

# 8. Copier les résultats
scp -r benchmarks/graphs/ <your-machine>:~/
```

## 📌 Points clés

### ✅ Avantages du système

- **Pas de privilèges root** : Fonctionne avec permissions utilisateur normales
- **Automatisation complète** : Script qui gère tout le processus
- **Visualisation riche** : Graphes multiples et rapport textuel
- **Données exportables** : Format CSV pour analyse externe
- **Compatible Grid5000** : Testé dans environnement distribué

### ⚠️ Limitations

- NFS nécessite un système de fichiers partagé configuré
- SCP nécessite une authentification SSH par clé (sans mot de passe)
- Les benchmarks locaux (localhost) ne montrent pas de vraies différences réseau

## 🐛 Dépannage

### Erreur de compilation

```bash
# Vérifier que toutes les classes sont présentes
ls -R src/

# Recompiler complètement
rm -rf bin && mkdir -p bin
find src -name "*.java" > sources.txt
javac -d bin -sourcepath src @sources.txt
```

### Pas de graphes générés

```bash
# Vérifier l'installation Python
python3 --version
pip3 list | grep -E "pandas|matplotlib|seaborn"

# Installer les dépendances
pip3 install --user pandas matplotlib seaborn
```

### Erreur NFS

```bash
# Vérifier que le répertoire existe
ls -la /tmp/wordcount_shared

# Créer le répertoire si nécessaire
mkdir -p /tmp/wordcount_shared
chmod 755 /tmp/wordcount_shared
```

## 📚 Fichiers ajoutés

### Code Java
- `src/config/FileTransferMethod.java` - Énumération des méthodes
- `src/benchmark/BenchmarkManager.java` - Collecte de métriques
- `src/config/Configuration.java` - Configuration modifiée
- `src/network/master/MasterCoordinator.java` - Support NFS/SCP modifié
- `src/scheduler/Main.java` - Arguments benchmarking ajoutés

### Scripts
- `scripts/run_benchmarks.sh` - Exécution automatisée
- `scripts/generate_benchmark_graphs.py` - Génération de graphes

### Documentation
- `BENCHMARK_README.md` - Ce fichier

## 🤝 Contribution

Pour ajouter de nouvelles métriques ou graphes :

1. Modifier `BenchmarkManager.java` pour collecter de nouvelles métriques
2. Modifier `generate_benchmark_graphs.py` pour ajouter de nouveaux graphes
3. Mettre à jour cette documentation

## 📧 Support

Pour toute question sur le système de benchmarking, référez-vous à :
- La documentation dans les commentaires du code
- Les exemples d'utilisation ci-dessus
- Les logs d'exécution dans `benchmarks/*/run_*.log`
