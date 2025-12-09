# Performance Benchmarking Guide

## Vue d'ensemble

Le système de benchmarking compare les performances entre deux modes:
- **NFS Mode**: Utilise le système de fichiers partagé Grid5000 (pas de transfert de fichiers)
- **SCP Mode**: Copie explicite des fichiers entre les nœuds

## Prérequis

1. **Réserver des nœuds Grid5000**:
   ```bash
   oarsub -I -l nodes=5,walltime=1:00:00
   ```

2. **Installer matplotlib** (pour les graphiques):
   ```bash
   pip3 install matplotlib numpy
   ```

## Utilisation

### Étape 1: Lancer le benchmark

```bash
cd ~/wordcount-distributed
bash benchmark.sh
```

Le script va:
- Tester plusieurs tailles de fichiers (1000, 5000, 10000, 50000, 100000 lignes)
- Faire 3 essais par test pour la fiabilité statistique
- Tester les modes NFS et SCP
- Sauvegarder les résultats en CSV dans `benchmark_results/`

**Durée estimée**: 30-60 minutes selon le nombre de nœuds

### Étape 2: Générer les graphiques

```bash
python3 benchmark_plot.py benchmark_results/benchmark_YYYYMMDD_HHMMSS.csv
```

Cela génère:
- **Graphique 1**: Temps d'exécution moyen avec barres d'erreur
- **Graphique 2**: Comparaison par diagramme à barres
- **Graphique 3**: Analyse de speedup (mode le plus rapide)
- **Graphique 4**: Box plots pour la variabilité

### Étape 3: Analyser les résultats

Le script affiche aussi un résumé textuel:
```
📊 PERFORMANCE SUMMARY
NFS Mode:
   1000 lines:  2.345s ± 0.123s (min: 2.234s, max: 2.489s)
   5000 lines:  4.567s ± 0.234s (min: 4.321s, max: 4.812s)
   ...

⚡ SPEEDUP ANALYSIS (NFS vs SCP)
   1000 lines: NFS is 1.23x faster (+23.4%) 🚀
   5000 lines: NFS is 1.45x faster (+45.2%) 🚀
```

## Configuration personnalisée

### Modifier les tailles de fichiers testées

Éditez `benchmark.sh` ligne 27:
```bash
FILE_SIZES=(1000 5000 10000 50000 100000)  # Ajoutez ou supprimez des tailles
```

### Modifier le nombre d'essais

Éditez `benchmark.sh` ligne 28:
```bash
NUM_RUNS=3  # Augmentez pour plus de précision (temps plus long)
```

### Modifier le timeout

Par défaut, chaque test a un timeout de 300 secondes (5 minutes).
Éditez lignes 92 et 119:
```bash
timeout 300 bash ...  # Changez 300 au nombre de secondes souhaité
```

## Format des résultats CSV

```
Mode,FileSize,Run,TimeTotal,TimeSplitting,TimeExecution,TimeAggregation,WordCount
NFS,1000,1,2.345,0,0,0,12000
SCP,1000,1,3.123,0,0,0,12000
...
```

**Colonnes**:
- `Mode`: NFS ou SCP
- `FileSize`: Nombre de lignes dans le fichier test
- `Run`: Numéro de l'essai (1 à NUM_RUNS)
- `TimeTotal`: Temps total d'exécution (secondes)
- `TimeSplitting`: Temps de division (actuellement 0)
- `TimeExecution`: Temps d'exécution (actuellement 0)
- `TimeAggregation`: Temps d'agrégation (actuellement 0)
- `WordCount`: Nombre total de mots comptés

## Logs de débogage

Les logs sont sauvegardés dans `/tmp/`:
- `/tmp/bench_nfs_{size}_{run}.log`: Logs du mode NFS
- `/tmp/bench_scp_{size}_{run}.log`: Logs du mode SCP

En cas d'échec, consultez ces fichiers pour le diagnostic.

## Conseils pour des résultats fiables

1. **Isolez le cluster**: Évitez de lancer d'autres jobs pendant le benchmark
2. **Nœuds homogènes**: Utilisez des nœuds du même cluster si possible
3. **Répétitions**: Augmentez NUM_RUNS pour des résultats plus stables
4. **Nettoyage**: Le script nettoie automatiquement entre les tests
5. **Warmup**: Le premier test peut être plus lent (cache froid)

## Dépannage

### Erreur: "Not in an OAR job"
```bash
# Réservez des nœuds d'abord
oarsub -I -l nodes=5,walltime=1:00:00
```

### Erreur: "matplotlib not found"
```bash
pip3 install --user matplotlib numpy
```

### Timeout sur les gros fichiers
Augmentez le timeout dans `benchmark.sh`:
```bash
timeout 600 bash ...  # 10 minutes au lieu de 5
```

### Résultats incohérents
- Vérifiez qu'aucun autre job ne tourne sur les nœuds
- Augmentez NUM_RUNS pour plus d'essais
- Vérifiez les logs dans `/tmp/bench_*.log`

## Exemple de sortie

```
╔══════════════════════════════════════════════════════════╗
║     PERFORMANCE BENCHMARKING TOOL                       ║
║     Tests: NFS vs SCP | Mono-site vs Multi-site         ║
╚══════════════════════════════════════════════════════════╝

📋 Benchmark Configuration:
   File sizes (lines): 1000 5000 10000 50000 100000
   Runs per test: 3
   Results file: benchmark_results/benchmark_20231209_143022.csv

🖥️  Cluster info:
   Total nodes: 5
   Workers: 4

═══════════════════════════════════════════════════════════
  Testing with file size: 1000 lines
═══════════════════════════════════════════════════════════

--- Run 1/3 ---
🧪 Testing NFS mode - Size: 1000 lines - Run: 1
   ⏱️  Time: 2.345s | Words: 12000
🧪 Testing SCP mode - Size: 1000 lines - Run: 1
   ⏱️  Time: 3.123s | Words: 12000

...

╔══════════════════════════════════════════════════════════╗
║     BENCHMARK COMPLETED                                  ║
╚══════════════════════════════════════════════════════════╝

📊 Results saved to: benchmark_results/benchmark_20231209_143022.csv

📈 Computing averages...
```
