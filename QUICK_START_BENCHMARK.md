# Guide de Démarrage Rapide : Benchmarking NFS vs SCP

## 🚀 En 3 étapes

### Étape 1 : Compilation
```bash
cd /home/user/wordcount-distributed
mkdir -p bin
find src -name "*.java" > /tmp/sources.txt
javac -d bin -sourcepath src @/tmp/sources.txt
```

### Étape 2 : Lancer le benchmark automatique
```bash
./scripts/run_benchmarks.sh --workers "[localhost]" --runs 3
```

### Étape 3 : Voir les résultats
```bash
# Graphes générés automatiquement dans :
ls -lh benchmarks/graphs/

# Lire le rapport
cat benchmarks/graphs/benchmark_report.txt
```

## 📊 Résultats attendus

Le système génère :
- ✅ **5 graphes PNG** comparant NFS et SCP
- ✅ **1 rapport texte** avec statistiques détaillées
- ✅ **Fichiers CSV** pour analyse externe

## 🔍 Test manuel (sans script automatique)

### Test SCP uniquement
```bash
java -cp bin scheduler.Main "[localhost]" --method=SCP --benchmark --output-dir=benchmarks/scp
```

### Test NFS uniquement
```bash
java -cp bin scheduler.Main "[localhost]" --method=NFS --benchmark --output-dir=benchmarks/nfs
```

### Générer les graphes manuellement
```bash
python3 scripts/generate_benchmark_graphs.py benchmarks/
```

## ⚙️ Configuration pour votre environnement

### Sur Grid5000
```bash
# 1. Réserver des nœuds
oarsub -I -l nodes=3,walltime=1:00:00

# 2. Construire la liste des workers
NODES=$(uniq $OAR_NODE_FILE | paste -sd,)
echo "Workers: [$NODES]"

# 3. Lancer le benchmark
./scripts/run_benchmarks.sh --workers "[$NODES]" --runs 5
```

### En local (testing)
```bash
# Simple test avec localhost
./scripts/run_benchmarks.sh --workers "[localhost]" --runs 3
```

## 📦 Dépendances Python (pour les graphes)

```bash
# Installer si nécessaire
pip3 install --user pandas matplotlib seaborn

# Vérifier l'installation
python3 -c "import pandas, matplotlib, seaborn; print('OK')"
```

## ❓ Problèmes courants

### "Command not found: javac"
```bash
# Charger Java sur Grid5000
module load java
```

### "No module named pandas"
```bash
# Installer les dépendances
pip3 install --user pandas matplotlib seaborn
```

### "Permission denied: ./scripts/run_benchmarks.sh"
```bash
# Rendre les scripts exécutables
chmod +x scripts/*.sh scripts/*.py
```

## 📈 Interpréter les résultats

### Graphe principal : comparison_by_operation.png
- Compare les temps moyens par type d'opération
- Plus la barre est courte, mieux c'est
- Regardez surtout "file_transfer"

### Rapport texte : benchmark_report.txt
```
Winner: NFS
Speedup: 2.5x faster than the alternative
```

## 🎯 Conseils pour de bons benchmarks

1. **Plusieurs runs** : `--runs 5` minimum pour des résultats fiables
2. **Environnement propre** : Pas d'autres tâches en cours
3. **Données réalistes** : Utilisez de vrais fichiers (part1.txt, part2.txt, etc.)
4. **Réseau réel** : Testez sur plusieurs machines, pas juste localhost

## 🔗 Documentation complète

Pour plus de détails, voir **BENCHMARK_README.md**

## ✅ Checklist

- [ ] Projet compilé (`bin/` contient les .class)
- [ ] Scripts exécutables (`chmod +x scripts/*`)
- [ ] Python installé avec pandas, matplotlib, seaborn
- [ ] Workers disponibles (local ou Grid5000)
- [ ] Espace disque suffisant pour les résultats

Prêt ? Lancez : `./scripts/run_benchmarks.sh`
