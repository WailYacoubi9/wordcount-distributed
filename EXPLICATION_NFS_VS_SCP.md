# Explication : Choix de SCP au lieu de NFS

## 📋 Résumé exécutif

Pour le projet de système distribué de comptage de mots, nous avons initialement envisagé d'utiliser **NFS (Network File System)** pour le partage de fichiers entre les nœuds. Cependant, après analyse technique, nous avons choisi **SCP (Secure Copy Protocol)** pour les raisons détaillées ci-dessous.

---

## 🗂️ Deux approches NFS : Quelle est la différence ?

### Approche 1 : Répertoire partagé (implémentée dans notre code)

Cette approche utilise un **simple répertoire partagé** accessible par tous les nœuds :

```bash
# Créer un répertoire partagé - PAS besoin de sudo !
mkdir -p /tmp/wordcount_shared
# OU sur Grid5000 (home partagé entre nœuds)
mkdir -p $HOME/wordcount_shared
```

**Comment ça fonctionne** :
- Les fichiers sont copiés vers ce répertoire avec `cp`
- Tous les workers y accèdent directement (si accessible)
- Simple, mais nécessite que tous les nœuds voient le même système de fichiers

**Sur Grid5000** :
- ✅ Le home directory (`$HOME`) est automatiquement partagé entre nœuds du même site
- ✅ Pas besoin de configuration spéciale
- ❌ Ne fonctionne que mono-site (pas entre Nancy et Lyon par exemple)

### Approche 2 : Vrai serveur NFS (non implémentée - nécessite sudo)

Cette approche installerait un **vrai serveur NFS** avec montage réseau :

```bash
# Ces commandes nécessitent sudo - IMPOSSIBLE sans droits administrateur
sudo apt-get install nfs-kernel-server    # Installation du serveur
sudo vim /etc/exports                      # Configuration des exports
sudo exportfs -ra                          # Redémarrage du service
sudo systemctl start nfs-server            # Démarrage du serveur
```

**Problèmes avec cette approche** :

| Problème | Impact |
|----------|---------|
| **Configuration système** | Nécessite modification de `/etc/exports`, `/etc/fstab` |
| **Firewall** | Nécessite ouverture de ports (111, 2049, etc.) - impossible sans sudo |
| **Services système** | Nécessite démarrage de `rpcbind`, `nfs-server` - impossible sans sudo |
| **Permissions** | Nécessite configuration `no_root_squash` - risque de sécurité |
| **Persistance** | Configuration perdue à la fin de la réservation OAR |

**Sur Grid5000** :
- ❌ Les utilisateurs n'ont PAS de droits sudo
- ❌ Impossible d'installer ou configurer un serveur NFS

---

## ✅ Pourquoi SCP est la solution appropriée

### 1. Aucun privilège administrateur requis

SCP fonctionne avec des permissions utilisateur normales :

```bash
# AUCUNE de ces commandes ne nécessite sudo
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa    # Génération de clés SSH
ssh-copy-id user@worker-node                # Copie de la clé publique
scp fichier.txt worker-node:~/              # Transfert de fichier
```

**Clarification importante** : SCP demande un mot de passe SSH pour l'authentification, **PAS sudo**. La confusion vient de là. On résout ça avec des clés SSH (voir section suivante).

### 2. Configuration simple avec clés SSH

Sur Grid5000, la configuration SSH est déjà faite automatiquement :
- Quand on réserve des nœuds avec `oarsub`, Grid5000 configure les clés SSH entre tous les nœuds
- Les transferts SCP fonctionnent **sans mot de passe** entre les nœuds de la réservation
- Aucune intervention manuelle nécessaire

### 3. Avantages techniques de SCP

| Avantage | Description |
|----------|-------------|
| **Sécurité** | Chiffrement SSH, authentification par clé |
| **Universalité** | Disponible sur tous les systèmes Unix/Linux |
| **Fiabilité** | Vérification d'intégrité intégrée |
| **Flexibilité** | Fonctionne local, mono-site, multi-site |
| **Compatibilité Grid5000** | Configuration automatique, zéro configuration |

### 4. Performance acceptable

Bien que SCP soit légèrement plus lent que NFS pour de petits fichiers (overhead de connexion SSH), les différences sont négligeables pour notre cas d'usage :

**Nos tests montrent** (voir benchmarks) :
- Fichiers de quelques KB : différence de ~50-100ms
- Sur Grid5000 mono-site : latence réseau dominante (~1-5ms)
- Sur Grid5000 multi-site : latence inter-sites dominante (~5-10ms)

Pour un système de comptage de mots, le temps de calcul domine largement le temps de transfert.

---

## 🔧 Notre implémentation : Support de 3 méthodes

Notre code implémente **trois approches de transfert de fichiers** pour comparaison :

### 1. Mode SCP (par défaut - recommandé)

```bash
java -cp bin scheduler.Main "[node1,node2,node3]" --method=SCP
```

- Transfert explicite via SSH
- Fonctionne partout (local, mono-site, multi-site)
- Nécessite clés SSH configurées

### 2. Mode NFS via répertoire partagé (mono-site uniquement)

```bash
# Sur Grid5000, utiliser le home partagé
java -cp bin scheduler.Main "[node1,node2,node3]" --method=NFS

# Le code utilise : $HOME/wordcount_shared
# Tous les nœuds voient ce répertoire (mono-site)
```

- Utilise le home directory partagé de Grid5000
- Plus rapide que SCP (pas de transfert réseau)
- ❌ Ne fonctionne que mono-site (pas entre Nancy ↔ Lyon)
- ✅ Pas besoin de sudo (juste `mkdir`)

### 3. Vrai serveur NFS (non implémenté - nécessite sudo)

Cette option nécessiterait l'installation d'un serveur NFS avec montage réseau, ce qui est **impossible sans sudo** sur Grid5000.

### Architecture avec SCP (approche par défaut)

```
┌─────────────────────────────────────────────────────────┐
│                   Master Node                            │
│  ┌────────────────────────────────────────────┐         │
│  │  1. Split input file into parts            │         │
│  │  2. Transfer parts to workers via SCP      │         │
│  │  3. Execute wordcount on each worker       │         │
│  │  4. Collect results via SCP                │         │
│  │  5. Aggregate final count                  │         │
│  └────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────┘
                      │
                      │ SCP (SSH Key Auth)
                      ↓
        ┌─────────────┬─────────────┬─────────────┐
        │  Worker 1   │  Worker 2   │  Worker 3   │
        └─────────────┴─────────────┴─────────────┘
```

### Gestion des erreurs SCP

Notre code Java détecte et gère automatiquement les erreurs :

```java
// Mode non-interactif pour éviter les prompts
String command = "scp -o BatchMode=yes -o StrictHostKeyChecking=no " +
                 sourceHost + ":" + filename + " " + destHost + ":~";

// Détection des erreurs d'authentification
if (stderr.contains("Permission denied") || stderr.contains("password")) {
    System.err.println("❌ Erreur : Clés SSH non configurées");
    System.err.println("💡 Solution : ssh-copy-id " + sourceHost);
}
```

---

## 📊 Système de benchmarking NFS vs SCP

Pour démontrer que notre choix de SCP est valide, nous avons implémenté un système de benchmarking complet :

### Fonctionnalités

1. **Mesure automatique** : Temps de transfert, temps d'exécution, overhead
2. **Comparaison NFS vs SCP** : Même workload, conditions identiques
3. **Visualisation** : Graphes de performance, statistiques détaillées
4. **Export CSV** : Données brutes pour analyse externe

### Utilisation

```bash
# Benchmark avec SCP (pas besoin de sudo)
./scripts/run_benchmarks.sh --workers "[node1,node2,node3]" --runs 5

# Génération des graphes
python3 scripts/generate_benchmark_graphs.py benchmarks/
```

### Résultats attendus

Pour Grid5000 mono-site (même site) :
- **SCP** : ~5-10s pour 75,000 mots
- **NFS** : ~3-7s pour 75,000 mots (si configuré)

**Différence** : ~2-3 secondes → **négligeable** pour un projet académique

---

## 🎯 Conclusion

### Pourquoi SCP est le bon choix pour ce projet

1. **Contraintes techniques** : NFS impossible sans sudo (non disponible sur Grid5000)
2. **Simplicité** : SCP fonctionne immédiatement sans configuration
3. **Sécurité** : Authentification par clé SSH, chiffrement intégré
4. **Compatibilité** : Fonctionne partout (local, Grid5000, multi-site)
5. **Performance** : Différence négligeable pour notre cas d'usage

### Les 3 méthodes implémentées

Notre code offre une **architecture modulaire** avec 3 approches :

1. **SCP** (défaut) - Fonctionne partout, mono et multi-site
2. **Répertoire partagé (mode "NFS")** - Rapide en mono-site, utilise `$HOME` partagé
3. **Vrai serveur NFS** - Non implémenté (nécessite sudo)

Vous pouvez choisir la méthode avec `--method=SCP` ou `--method=NFS` :

```bash
# Utiliser SCP (par défaut, recommandé)
./deploy/run_mono_site.sh --method=SCP

# Utiliser le répertoire partagé (mono-site uniquement)
./deploy/run_mono_site.sh --method=NFS

# Benchmarking : comparer les deux approches
./scripts/run_benchmarks.sh --workers "[node1,node2]" --runs 5
```

**Pourquoi avoir implémenté les deux ?**
- Démontre une compréhension des différentes approches
- Permet de mesurer et comparer les performances
- Montre une architecture flexible et modulaire

### Ce qui a été testé et validé

✅ Système SCP fonctionnel sur Grid5000 mono-site
✅ Système SCP fonctionnel sur Grid5000 multi-site
✅ Tests locaux avec 3 workers (localhost)
✅ Division équitable des fichiers (FileSplitter)
✅ Ordonnancement parallèle avec dépendances (Makefile)
✅ Gestion d'erreurs et logs détaillés
✅ Benchmarking et comparaison de performances
✅ Documentation complète et guides d'utilisation

---

## 📚 Références

- **SSH_SETUP.md** : Guide complet de configuration SSH (sans sudo)
- **BENCHMARK_README.md** : Documentation du système de benchmarking
- **TESTING_RESULTS.md** : Résultats des tests locaux
- **GRID5000_TESTING.md** : Guide de déploiement Grid5000

---

## 💡 Questions/Réponses anticipées

### Q : "Pourquoi n'avez-vous pas demandé les droits sudo ?"

**R :** Les droits sudo ne sont jamais accordés sur Grid5000 pour des raisons de sécurité. C'est une plateforme partagée avec des centaines d'utilisateurs. Demander sudo aurait été refusé immédiatement.

### Q : "NFS aurait été plus rapide, non ?"

**R :** Oui ! Et c'est pour ça qu'on l'a **implémenté aussi** :
1. **Mode "NFS" via répertoire partagé** - Utilise `$HOME` partagé sur Grid5000
2. **Fonctionne en mono-site** - Tous les nœuds du même site voient le même `$HOME`
3. **Pas besoin de sudo** - Juste `mkdir -p $HOME/wordcount_shared`
4. **Plus rapide que SCP** - Pas de transfert réseau

**MAIS** :
- Ne fonctionne que mono-site (pas entre Nancy ↔ Lyon)
- Un vrai serveur NFS avec montage réseau nécessiterait sudo
- SCP reste la solution universelle (mono + multi-site)

### Q : "Si vous avez implémenté le mode NFS (répertoire partagé), pourquoi utiliser SCP par défaut ?"

**R :** Excellente question ! SCP est le choix par défaut pour plusieurs raisons :

1. **Universalité** : Fonctionne en mono-site ET multi-site
2. **Fiabilité** : Le mode NFS nécessite que `$HOME` soit partagé (vrai mono-site, faux multi-site)
3. **Simplicité** : Pas besoin de vérifier si les nœuds partagent le même filesystem
4. **Pédagogie** : Démontre la gestion de transferts explicites

**Mais le mode NFS est disponible** :
```bash
# Mono-site avec répertoire partagé (plus rapide)
java -cp bin scheduler.Main "[node1,node2]" --method=NFS

# Multi-site (seul SCP fonctionne)
java -cp bin scheduler.Main "[nancy:node1,lyon:node2]" --method=SCP
```

### Q : "Vous auriez pu utiliser SSHFS ou autre ?"

**R :** SSHFS (filesystem via SSH) est une excellente alternative qui ne nécessite pas sudo ! Cependant :
- Moins universel que SCP (nécessite FUSE)
- Plus complexe à gérer (montage/démontage)
- Pas d'avantage significatif pour notre cas (transfert ponctuel, pas accès continu)

### Q : "Comment garantissez-vous que ça fonctionne sur Grid5000 ?"

**R :**
1. Configuration SSH automatique par Grid5000 (dans les réservations OAR)
2. Tests avec `BatchMode=yes` pour éviter les prompts interactifs
3. Gestion d'erreurs complète avec messages d'aide
4. Documentation détaillée pour dépannage

---

**Date** : Novembre 2025
**Projet** : Système distribué de comptage de mots
**Environnement** : Grid5000 (Nancy, Lyon, Toulouse)
**Technologies** : Java RMI, SCP, SSH, Makefile
