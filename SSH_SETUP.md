# Configuration SSH pour SCP sans mot de passe

## ⚠️ Clarification importante

**SCP ne demande PAS sudo** - il demande un **mot de passe SSH** pour l'authentification.

Dans un programme Java, on ne peut pas saisir de mot de passe interactivement. Il faut donc configurer l'authentification par **clés SSH**.

## 🔑 Configuration des clés SSH (sans sudo !)

### Sur votre machine locale

```bash
# 1. Générer une paire de clés SSH (si pas déjà fait)
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# Explication :
# -t rsa       : Type de clé (RSA)
# -b 4096      : Taille de la clé (4096 bits)
# -N ""        : Pas de passphrase (important pour automatisation)
# -f ~/.ssh/id_rsa : Fichier de sortie

# 2. Vérifier que la clé a été créée
ls -lh ~/.ssh/id_rsa*
# Devrait afficher :
# -rw------- 1 user user 3.3K ... id_rsa         (clé privée)
# -rw-r--r-- 1 user user  742 ... id_rsa.pub     (clé publique)
```

### Copier la clé vers les machines distantes

```bash
# Méthode 1 : Utiliser ssh-copy-id (le plus simple)
ssh-copy-id user@nancy-2.grid5000.fr
ssh-copy-id user@nancy-3.grid5000.fr

# Méthode 2 : Copie manuelle (si ssh-copy-id non disponible)
cat ~/.ssh/id_rsa.pub | ssh user@nancy-2.grid5000.fr "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Méthode 3 : Sur Grid5000 (dans une réservation)
# Les clés sont souvent déjà configurées automatiquement !
```

### Tester la configuration

```bash
# Test 1 : Connexion SSH (ne devrait PAS demander de mot de passe)
ssh nancy-2.grid5000.fr 'echo "SSH OK"'

# Test 2 : Transfert SCP (ne devrait PAS demander de mot de passe)
echo "test" > test.txt
scp test.txt nancy-2.grid5000.fr:~
rm test.txt

# Test 3 : Vérifier avec BatchMode
scp -o BatchMode=yes test.txt nancy-2.grid5000.fr:~
# Si ça échoue, les clés ne sont pas configurées correctement
```

## 🏫 Configuration spécifique Grid5000

### Grid5000 configure automatiquement SSH

Quand vous réservez des nœuds avec `oarsub`, Grid5000 :
1. ✅ Configure automatiquement les clés SSH entre les nœuds
2. ✅ Permet SSH sans mot de passe entre tous les nœuds de la réservation
3. ✅ Configure StrictHostKeyChecking à "no"

**Donc normalement, vous n'avez RIEN à faire !**

### Vérification sur Grid5000

```bash
# 1. Réserver des nœuds
oarsub -I -l nodes=3,walltime=1:00:00

# 2. Vérifier la configuration SSH
cat ~/.ssh/config

# 3. Tester la connexion
ssh $(head -1 $OAR_NODE_FILE) 'hostname'

# 4. Si ça fonctionne sans mot de passe, c'est bon !
```

### Si ça ne fonctionne pas sur Grid5000

```bash
# Vérifier que le fichier authorized_keys existe
ssh $(head -1 $OAR_NODE_FILE) 'ls -la ~/.ssh/authorized_keys'

# Vérifier les permissions (très important !)
ssh $(head -1 $OAR_NODE_FILE) 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'

# Déboguer SSH
ssh -v $(head -1 $OAR_NODE_FILE) 'echo OK'
```

## 💻 Configuration pour tests locaux (localhost)

Pour tester en local avec `[localhost]` :

```bash
# 1. Copier votre propre clé publique dans authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 2. Tester
ssh localhost 'echo OK'
# Ne devrait PAS demander de mot de passe

# 3. Si ça demande encore un mot de passe, vérifier sshd_config
# (mais normalement pas besoin de sudo)
```

## 🔧 Améliorations du code

J'ai amélioré le code pour :

### 1. Mode non-interactif automatique

```java
// Ajout de BatchMode=yes pour éviter les prompts
String command = "scp -o BatchMode=yes -o StrictHostKeyChecking=no " +
               sourceHost + ":" + filename + " " + destHost + ":~";
```

Options SCP utilisées :
- `-o BatchMode=yes` : Empêche TOUS les prompts interactifs
- `-o StrictHostKeyChecking=no` : Accepte automatiquement les nouvelles clés d'hôte

### 2. Détection d'erreurs améliorée

Le code lit maintenant stderr et détecte :
- Erreurs d'authentification
- Demandes de mot de passe
- Affiche des instructions de résolution

## 🎯 Récapitulatif

### Pourquoi SCP demande un mot de passe ?

❌ **Ce n'est PAS sudo** - c'est l'authentification SSH
✅ **Solution** : Configurer les clés SSH (aucun sudo requis)

### Étapes pour résoudre

```bash
# 1. Générer une clé SSH (si pas déjà fait)
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# 2. Copier vers les workers
ssh-copy-id nancy-2.grid5000.fr

# 3. Tester
ssh nancy-2.grid5000.fr 'echo OK'
```

### Sur Grid5000

**Normalement rien à faire !** Les clés sont configurées automatiquement.

Si problème, vérifier :
```bash
# Les permissions des fichiers SSH
ls -la ~/.ssh/
# Devrait être :
# drwx------  .ssh/
# -rw-------  id_rsa
# -rw-r--r--  id_rsa.pub
# -rw-------  authorized_keys
```

## 🐛 Dépannage

### Erreur : "Permission denied (publickey)"

```bash
# Solution : Vérifier que la clé publique est dans authorized_keys
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Erreur : "Host key verification failed"

```bash
# Solution : Désactiver temporairement la vérification
# (déjà fait dans le code avec -o StrictHostKeyChecking=no)
```

### SCP fonctionne manuellement mais pas dans Java

```bash
# Vérifier que BatchMode fonctionne
scp -o BatchMode=yes test.txt nancy-2.grid5000.fr:~

# Si ça échoue, les clés ne sont pas configurées
```

## 📚 Ressources

- [Grid5000 SSH Documentation](https://www.grid5000.fr/w/SSH)
- [SSH Key Setup Guide](https://www.ssh.com/academy/ssh/copy-id)
- Man pages : `man ssh-keygen`, `man ssh-copy-id`, `man scp`

## ✅ Vérification finale

Après configuration, ces commandes doivent fonctionner **sans demander de mot de passe** :

```bash
# Test SSH
ssh nancy-2.grid5000.fr 'hostname'

# Test SCP
scp test.txt nancy-2.grid5000.fr:~

# Test SCP en mode batch (utilisé par Java)
scp -o BatchMode=yes test.txt nancy-2.grid5000.fr:~
```

Si tout fonctionne, le benchmarking Java fonctionnera également ! 🎉
