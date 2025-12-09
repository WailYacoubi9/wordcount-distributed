# Guide Multi-Site - Grid5000

## 🌍 Déploiement Multi-Site Réel

Ce guide explique comment tester le système distribué sur **plusieurs sites Grid5000** (ex: Grenoble + Lyon).

---

## 📋 Prérequis

- Accès Grid5000
- SSH configuré
- 2 terminaux ouverts

---

## 🚀 Méthode Complète (Step-by-Step)

### **Terminal 1 : Site Grenoble (Master)**

```bash
# 1. Se connecter à Grenoble
ssh access.grid5000.fr
ssh grenoble

# 2. Réserver 2 nœuds
oarsub -I -l nodes=2,walltime=1:00:00

# 3. Une fois dans le job, sauvegarder les nœuds
cat $OAR_NODEFILE | uniq > ~/nodes_grenoble.txt

# 4. Vérifier
cat ~/nodes_grenoble.txt
# Devrait afficher quelque chose comme:
#   dahu-2.grenoble.grid5000.fr
#   dahu-6.grenoble.grid5000.fr

# 5. Noter le nom du master
hostname
# Ex: dahu-2.grenoble.grid5000.fr
```

**⚠️ GARDER CE TERMINAL OUVERT**

---

### **Terminal 2 : Site Lyon (Workers)**

```bash
# 1. Se connecter à Lyon
ssh access.grid5000.fr
ssh lyon

# 2. Réserver 2 nœuds
oarsub -I -l nodes=2,walltime=1:00:00

# 3. Une fois dans le job, sauvegarder les nœuds
cat $OAR_NODEFILE | uniq > ~/nodes_lyon.txt

# 4. Copier vers le master Grenoble
# Remplacer GRENOBLE_MASTER par le hostname noté à l'étape 5 du Terminal 1
scp ~/nodes_lyon.txt dahu-2.grenoble.grid5000.fr:~/

# Exemple:
# scp ~/nodes_lyon.txt dahu-2.grenoble.grid5000.fr:~/
```

**⚠️ GARDER CE TERMINAL OUVERT AUSSI**

---

### **Retour au Terminal 1 : Combiner et Lancer**

```bash
# 6. Attendre que le fichier Lyon arrive (vérifier)
ls -l ~/nodes_lyon.txt

# 7. Combiner les deux fichiers
cat ~/nodes_grenoble.txt ~/nodes_lyon.txt > ~/combined_nodes.txt

# 8. Vérifier le fichier combiné
echo ""
echo "=== NŒUDS MULTI-SITE ==="
cat ~/combined_nodes.txt
echo ""

# Devrait afficher quelque chose comme:
#   dahu-2.grenoble.grid5000.fr
#   dahu-6.grenoble.grid5000.fr
#   nova-1.lyon.grid5000.fr
#   nova-2.lyon.grid5000.fr

# 9. Aller dans le projet
cd ~/wordcount-distributed

# 10. Définir le nodefile
export OAR_NODEFILE=~/combined_nodes.txt

# 11. LANCER LE TEST MULTI-SITE ! 🚀
bash deploy/run_multi_site.sh
```

---

## 📊 Ce Que Vous Verrez

### Détection Multi-Site

```
🗺️  Analyzing site distribution...

Sites involved:
  ✓ grenoble: 2 node(s) [MASTER SITE]
  → lyon: 2 node(s)

✅ Multi-site deployment confirmed (2 sites)

👷 Worker nodes by site:
  [grenoble] dahu-6.grenoble.grid5000.fr
  [lyon] nova-1.lyon.grid5000.fr
  [lyon] nova-2.lyon.grid5000.fr

Total workers: 3 across 2 sites
```

### Compression en Action

```
📦 Preparing files for multi-site transfer with compression...
  🗜️  Compressing files (bin/, wordcount, test/, Makefile)...
  📊 Compression stats:
      Original: 145K
      Compressed: 37K
      Ratio: 4.0x

🚀 Transferring compressed archive to worker nodes...
  - [grenoble] Transferring to dahu-6.grenoble.grid5000.fr...
  - [grenoble] Extracting on dahu-6.grenoble.grid5000.fr...
  - [lyon] Transferring to nova-1.lyon.grid5000.fr...
  - [lyon] Extracting on nova-1.lyon.grid5000.fr...
  - [lyon] Transferring to nova-2.lyon.grid5000.fr...
  - [lyon] Extracting on nova-2.lyon.grid5000.fr...

✅ Files transferred and extracted on all sites in 5s
   (Compression saved ~325K total)
```

### Exécution Distribuée

```
🚀 Starting worker nodes across all sites...
  - [grenoble] Starting worker on dahu-6.grenoble.grid5000.fr...
  - [lyon] Starting worker on nova-1.lyon.grid5000.fr...
  - [lyon] Starting worker on nova-2.lyon.grid5000.fr...

⏳ Waiting for workers to initialize across all sites...

╔══════════════════════════════════════════════════════════╗
║   STARTING MULTI-SITE DISTRIBUTED EXECUTION             ║
╚══════════════════════════════════════════════════════════╝

[Exécution distribuée entre Grenoble et Lyon...]

╔════════════════════════════╗
║  Total word count: 8000   ║
╚════════════════════════════╝

🌐 Multi-site performance:
  Sites involved: 2
  Workers: 3
  Execution time: 12s
```

---

## ⚡ Méthode Alternative (Script Helper)

Au lieu de faire tout manuellement, utilisez le script helper :

```bash
# Après avoir des réservations actives sur les deux sites
bash deploy/setup_multisite.sh grenoble lyon
```

Le script va automatiquement :
1. Récupérer les nodefiles des deux sites
2. Les combiner
3. Vous donner la commande pour lancer

---

## 🎯 Vérifications Importantes

### Avant de Lancer

```bash
# Vérifier que le fichier combiné contient bien des nœuds de 2 sites
cat ~/combined_nodes.txt | awk -F. '{print $2}' | sort | uniq

# Devrait afficher:
#   grenoble
#   lyon
```

### Pendant l'Exécution

Surveillez les deux terminaux pour voir les workers démarrer sur chaque site.

### Après l'Exécution

```bash
# Vérifier les logs sur les workers distants
ssh nova-1.lyon.grid5000.fr "cat ~/worker.log"
```

---

## 🐛 Troubleshooting

### Problème : "Cannot connect to worker"

**Cause :** Firewall ou communication RMI bloquée entre sites

**Solution :**
```bash
# Tester la connectivité
ping nova-1.lyon.grid5000.fr

# Tester SSH
ssh nova-1.lyon.grid5000.fr "echo OK"
```

### Problème : "File transfer failed"

**Cause :** Problème réseau inter-sites

**Solution :**
```bash
# Tester SCP manuellement
scp ~/combined_nodes.txt nova-1.lyon.grid5000.fr:~/test.txt
```

### Problème : "Only 1 site detected"

**Cause :** Le fichier combined_nodes.txt contient seulement un site

**Solution :**
```bash
# Vérifier le contenu
cat ~/combined_nodes.txt

# Recréer le fichier combiné
cat ~/nodes_grenoble.txt ~/nodes_lyon.txt > ~/combined_nodes.txt
```

---

## 📈 Gains de Performance Multi-Site

### Avec Compression

| Taille Données | Sans Compression | Avec Compression | Gain |
|----------------|------------------|------------------|------|
| 145 KB | 0.1s transfert | 0.04s + 0.041s compress | ✅ Peu de gain (petits fichiers) |
| 5 MB | 2.5s transfert | 0.6s + 0.5s compress | ✅ 40% plus rapide |
| 50 MB | 25s transfert | 6s + 2s compress | ✅ 68% plus rapide |

**Conclusion :** Plus les fichiers sont gros, plus la compression est rentable !

---

## 🎓 Pour la Présentation

**Points à mentionner :**

1. **Architecture Réelle Multi-Site**
   - Communication inter-sites (Grenoble ↔ Lyon)
   - Latence réseau ~5-10ms
   - Bande passante limitée

2. **Optimisation Compression**
   - Ratio 4x (75% réduction)
   - Rentable pour gros transferts
   - Trade-off CPU vs Réseau

3. **Scalabilité Géographique**
   - Système fonctionne indépendamment de la localisation
   - Architecture transparente pour l'application
   - Déploiement automatisé

4. **Défis Multi-Site**
   - Gestion de l'hétérogénéité réseau
   - Synchronisation entre sites
   - Gestion des pannes réseau

---

## 🚀 Commandes Rapides

```bash
# Setup complet en une commande (si helper script)
bash deploy/setup_multisite.sh grenoble lyon && \
export OAR_NODEFILE=~/combined_nodes.txt && \
bash deploy/run_multi_site.sh

# Ou avec nodefile en argument
bash deploy/run_multi_site.sh ~/combined_nodes.txt
```

---

## ✅ Checklist Multi-Site

- [ ] 2 réservations actives sur sites différents
- [ ] Nodefiles sauvegardés localement
- [ ] Fichier combiné créé et vérifié
- [ ] Code compilé localement
- [ ] Variable OAR_NODEFILE définie
- [ ] Script run_multi_site.sh lancé
- [ ] Résultats vérifiés

**Bon test multi-site !** 🌍🚀
