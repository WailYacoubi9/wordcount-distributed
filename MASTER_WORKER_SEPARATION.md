# Fix: Master/Worker Separation

## 🐛 Problème Identifié

Le nœud master était inclus dans la liste des workers, ce qui causait:

1. **Le master exécutait des tâches de comptage** - Il ne devrait faire que la coordination et l'agrégation
2. **Nombre de workers incorrect** - Avec 4 nœuds réservés, on avait 4 workers au lieu de 3
3. **Makefile généré incorrect** - 4 fichiers `part*.txt` et `count*.txt` au lieu de 3

### Exemple avec 4 nœuds réservés

**AVANT (incorrect):**
```
Nœuds réservés: dahu-15, dahu-3, dahu-30, dahu-31

Architecture:
- dahu-15 = MASTER + WORKER  ❌ (fait count2.txt)
- dahu-3  = WORKER           (fait count3.txt)
- dahu-30 = WORKER           (fait count1.txt)
- dahu-31 = WORKER           (fait count4.txt)

Résultat:
- 4 workers (master inclus)
- 4 fichiers part (part1-4.txt)
- 4 fichiers count (count1-4.txt)
- Master exécute des tâches de worker ❌
```

**APRÈS (correct):**
```
Nœuds réservés: dahu-15, dahu-3, dahu-30, dahu-31

Architecture:
- dahu-15 = MASTER uniquement ✅ (coordination + agrégation)
- dahu-3  = WORKER            (fait count1.txt)
- dahu-30 = WORKER            (fait count2.txt)
- dahu-31 = WORKER            (fait count3.txt)

Résultat:
- 3 workers (master exclu)
- 3 fichiers part (part1-3.txt)
- 3 fichiers count (count1-3.txt)
- Master ne fait QUE la coordination ✅
```

---

## ✅ Correction Implémentée

### 1. Fichier: `src/cluster/ClusterManager.java`

**Changement principal (ligne 59-64):**

```java
// AVANT
this.nodes = Collections.synchronizedList(tempNodes);  // Tous les nœuds
this.masterNode = tempNodes.get(0);                    // Master aussi dans nodes ❌

// APRÈS
this.masterNode = tempNodes.get(0);                    // Premier = master
List<ComputeNode> workerNodes = new ArrayList<>(
    tempNodes.subList(1, tempNodes.size())             // Reste = workers
);
this.nodes = Collections.synchronizedList(workerNodes); // Master exclu ✅
```

**Logs améliorés:**
```java
System.out.println("[CLUSTER] Master node: " + masterNode.hostname + " (coordination only)");
System.out.println("[CLUSTER] Worker nodes: " + workerNodes.size());
for (ComputeNode worker : workerNodes) {
    System.out.println("[CLUSTER]   - " + worker.hostname + ":" + worker.port);
}
System.out.println("[CLUSTER] ✅ Cluster initialized: 1 master + " + workerNodes.size() + " worker(s)");
```

### 2. Fichier: `src/config/Configuration.java`

**Mise à jour de MIN_WORKER_NODES:**

```java
// AVANT
public static final int MIN_WORKER_NODES = 1;

// APRÈS
// Note: These are TOTAL nodes (master + workers)
// Minimum 2 = 1 master + 1 worker
public static final int MIN_WORKER_NODES = 2;
```

**Raison:** On a besoin d'au moins 2 nœuds maintenant (1 master + 1 worker minimum)

---

## 📊 Impact

### Avec 4 nœuds réservés (Grid5000)

| Aspect | Avant | Après |
|--------|-------|-------|
| **Master** | dahu-15 (aussi worker) | dahu-15 (coordination uniquement) |
| **Workers** | 4 (dahu-15,3,30,31) | 3 (dahu-3,30,31) |
| **Fichiers part** | part1-4.txt | part1-3.txt |
| **Fichiers count** | count1-4.txt | count1-3.txt |
| **Master exécute count** | ✅ Oui (count2.txt) | ❌ Non |
| **Distribution** | 1000/4 = 250 lignes/worker | 1000/3 = 333-334 lignes/worker |

### Logs Attendus

**AVANT:**
```
[CLUSTER] Initializing cluster with 4 nodes:
[CLUSTER]   - dahu-15.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-3.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-30.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-31.grenoble.grid5000.fr:3000
[CLUSTER] Master node: dahu-15.grenoble.grid5000.fr
[CLUSTER] ✅ Cluster initialized with 4 worker(s)

[SPLITTER] Total lines in input: 1000
[SPLITTER] Base lines per worker: 250
[SPLITTER] Workers with extra line: 0

[TASK-NFS count2.txt] Assigned to worker: dahu-15  ❌ MASTER fait du worker!
```

**APRÈS:**
```
[CLUSTER] Initializing cluster with 4 nodes:
[CLUSTER]   - dahu-15.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-3.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-30.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-31.grenoble.grid5000.fr:3000
[CLUSTER] Master node: dahu-15.grenoble.grid5000.fr (coordination only)
[CLUSTER] Worker nodes: 3
[CLUSTER]   - dahu-3.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-30.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-31.grenoble.grid5000.fr:3000
[CLUSTER] ✅ Cluster initialized: 1 master + 3 worker(s)

[SPLITTER] Total lines in input: 1000
[SPLITTER] Base lines per worker: 333
[SPLITTER] Workers with extra line: 1

[TASK-NFS count1.txt] Assigned to worker: dahu-3   ✅
[TASK-NFS count2.txt] Assigned to worker: dahu-30  ✅
[TASK-NFS count3.txt] Assigned to worker: dahu-31  ✅
```

**Différences clés:**
- ✅ Master clairement identifié comme "coordination only"
- ✅ Liste des workers affichée séparément
- ✅ "1 master + 3 worker(s)" au lieu de "4 worker(s)"
- ✅ 3 fichiers part/count au lieu de 4
- ✅ Distribution: 333-334 lignes/worker au lieu de 250

---

## 🔧 Makefile Généré

### AVANT (4 nœuds → 4 workers)

```makefile
# 4 fichiers count
/home/wyacoubi/nfs_wordcount/count1.txt: /home/wyacoubi/nfs_wordcount/part1.txt wordcount
/home/wyacoubi/nfs_wordcount/count2.txt: /home/wyacoubi/nfs_wordcount/part2.txt wordcount
/home/wyacoubi/nfs_wordcount/count3.txt: /home/wyacoubi/nfs_wordcount/part3.txt wordcount
/home/wyacoubi/nfs_wordcount/count4.txt: /home/wyacoubi/nfs_wordcount/part4.txt wordcount

# Agrégation de 4 fichiers
/home/wyacoubi/nfs_wordcount/total.txt: count1.txt count2.txt count3.txt count4.txt
    cat count1.txt count2.txt count3.txt count4.txt | awk ...
```

### APRÈS (4 nœuds → 3 workers)

```makefile
# 3 fichiers count
/home/wyacoubi/nfs_wordcount/count1.txt: /home/wyacoubi/nfs_wordcount/part1.txt wordcount
/home/wyacoubi/nfs_wordcount/count2.txt: /home/wyacoubi/nfs_wordcount/part2.txt wordcount
/home/wyacoubi/nfs_wordcount/count3.txt: /home/wyacoubi/nfs_wordcount/part3.txt wordcount

# Agrégation de 3 fichiers
/home/wyacoubi/nfs_wordcount/total.txt: count1.txt count2.txt count3.txt
    cat count1.txt count2.txt count3.txt | awk ...
```

---

## 🚀 Comment Retester

### Sur Grid5000

```bash
# 1. Pull les changements
cd ~/wordcount-distributed
git pull

# 2. Recompiler
javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
      src/parser/*.java src/network/worker/*.java \
      src/network/master/*.java src/scheduler/*.java

# 3. Créer un fichier de test (si pas déjà fait)
for i in {1..1000}; do echo "ligne de test numéro $i avec plusieurs mots"; done > bigtest.txt

# 4. Lancer le test NFS
bash deploy/run_nfs_home.sh bigtest.txt
```

### Vérifications Attendues

**1. Logs de cluster:**
```
[CLUSTER] Master node: dahu-15.grenoble.grid5000.fr (coordination only)
[CLUSTER] Worker nodes: 3
[CLUSTER]   - dahu-3.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-30.grenoble.grid5000.fr:3000
[CLUSTER]   - dahu-31.grenoble.grid5000.fr:3000
[CLUSTER] ✅ Cluster initialized: 1 master + 3 worker(s)
```

**2. Logs de split:**
```
[SPLITTER] Total lines in input: 1000
[SPLITTER] Base lines per worker: 333
[SPLITTER] Workers with extra line: 1
[SPLITTER] Created .../part1.txt with 334 lines  ← 333 + 1
[SPLITTER] Created .../part2.txt with 333 lines
[SPLITTER] Created .../part3.txt with 333 lines
```

**3. Tâches assignées:**
```
[TASK-NFS count1.txt] Assigned to worker: dahu-3    ✅
[TASK-NFS count2.txt] Assigned to worker: dahu-30   ✅
[TASK-NFS count3.txt] Assigned to worker: dahu-31   ✅
```

**dahu-15 (master) ne devrait JAMAIS apparaître dans "Assigned to worker"!**

**4. Fichiers créés:**
```bash
ls /home/wyacoubi/nfs_wordcount/
# Devrait montrer:
# part1.txt, part2.txt, part3.txt  (3 fichiers, pas 4!)
# count1.txt, count2.txt, count3.txt  (3 fichiers, pas 4!)
# total.txt
```

**5. Makefile généré:**
```bash
cat /home/wyacoubi/nfs_wordcount/Makefile.generated
# Devrait avoir 3 targets count (pas 4)
```

**6. Résultat total:**
```
╔════════════════════════════╗
║  Total word count: 8000     ║
╚════════════════════════════╝
```

Même résultat (1000 lignes × 8 mots = 8000), mais calculé par 3 workers au lieu de 4!

---

## 📝 Fichiers Modifiés

1. **`src/cluster/ClusterManager.java`**
   - Master exclu de la liste des workers
   - Logs améliorés montrant séparation master/workers

2. **`src/config/Configuration.java`**
   - MIN_WORKER_NODES: 1 → 2 (besoin de 1 master + 1 worker minimum)

---

## ✅ Bénéfices

1. **Architecture correcte** - Master et workers ont des rôles distincts
2. **Logs clairs** - On voit immédiatement qui est master et qui est worker
3. **Distribution optimale** - Seuls les vrais workers reçoivent du travail
4. **Makefile précis** - Nombre de tâches = nombre de workers réels
5. **Scalabilité** - Fonctionne de 2 à 1000 nœuds (1 master + 1-999 workers)

---

## 🎯 Résumé

**Problème:** Master inclus dans la liste des workers → fait du travail de comptage

**Solution:** Exclure le master de `this.nodes` → seuls les workers font le comptage

**Impact:** Avec N nœuds réservés → 1 master + (N-1) workers

**Résultat:** Architecture propre et conforme aux bonnes pratiques de systèmes distribués! ✅
