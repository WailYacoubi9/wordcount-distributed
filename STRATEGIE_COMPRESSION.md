# Stratégie de compression pour fichiers d'entrée

## 📋 Vue d'ensemble

La compression des fichiers avant transfert peut **réduire significativement** le temps de transfert réseau, particulièrement pour :
- Fichiers texte volumineux (forte compressibilité)
- Transferts SCP sur réseaux lents ou latents
- Scénarios multi-site (Nancy ↔ Lyon)

---

## 📊 Analyse du compromis compression/transfert

### Temps total = Temps compression + Temps transfert + Temps décompression

```
Sans compression:
  Total = 0 + T_transfert + 0

Avec compression:
  Total = T_compress + T_transfert_réduit + T_decompress
```

**Quand la compression est bénéfique :**
- `T_compress + T_decompress < Gain_transfert`
- Typiquement : fichiers > 1 MB, réseau lent, taux compression > 50%

---

## 🎯 Stratégies de compression proposées

### Stratégie 1 : Compression GZIP par défaut (RECOMMANDÉE)

**Principe** : Compresser chaque part avant transfert SCP

**Avantages** :
- ✅ Très bonne compression pour texte (~70-80%)
- ✅ Native en Java (`java.util.zip.GZIPOutputStream`)
- ✅ Pas besoin d'outils externes
- ✅ Compatible avec commande système `gunzip`

**Implémentation** :
```java
// Dans FileSplitter.java
public static List<String> splitAndCompressFile(String inputFile,
                                                 int numWorkers,
                                                 String outputPrefix) {
    // 1. Découper le fichier en parts
    List<String> parts = splitFileEquitably(inputFile, numWorkers, outputPrefix);

    // 2. Compresser chaque part
    List<String> compressedParts = new ArrayList<>();
    for (String part : parts) {
        String compressed = compressFile(part);
        compressedParts.add(compressed);
    }

    return compressedParts;
}

private static String compressFile(String inputFile) throws IOException {
    String outputFile = inputFile + ".gz";

    try (FileInputStream fis = new FileInputStream(inputFile);
         FileOutputStream fos = new FileOutputStream(outputFile);
         GZIPOutputStream gzos = new GZIPOutputStream(fos)) {

        byte[] buffer = new byte[1024 * 64]; // 64KB buffer
        int len;
        while ((len = fis.read(buffer)) != -1) {
            gzos.write(buffer, 0, len);
        }
    }

    System.out.println("[COMPRESS] " + inputFile + " -> " + outputFile);
    return outputFile;
}
```

**Workflow complet** :
```
Master:
  1. Split input.txt → part1.txt, part2.txt, part3.txt
  2. Compress → part1.txt.gz, part2.txt.gz, part3.txt.gz
  3. SCP transfer → worker nodes

Worker:
  4. Decompress → part1.txt
  5. Execute wordcount
  6. Return results
```

**Gains attendus** :
- Fichier texte 10 MB → ~2-3 MB compressé (70-80% réduction)
- Sur réseau 100 Mbps : gain de ~6-7 secondes
- Sur Grid5000 multi-site : gain de ~2-3 secondes

---

### Stratégie 2 : Compression à la volée (AVANCÉE)

**Principe** : Compresser pendant le transfert SCP

**Avantages** :
- ✅ Pas de fichiers intermédiaires
- ✅ Pipeline efficace
- ✅ Économie d'espace disque

**Implémentation** :
```bash
# Dans MasterCoordinator.java, commande SCP modifiée
# Compression à la volée avec pipe
cat part1.txt | gzip | ssh worker1 "gunzip > part1.txt"

# Ou avec SCP et compression
scp -C part1.txt worker1:~/  # -C active la compression SSH
```

**Code Java** :
```java
private static boolean transferFileCompressed(String sourceHost,
                                              String destHost,
                                              String filename) {
    try {
        // Option -C active la compression SSH native
        String command = "scp -C -o BatchMode=yes " +
                        sourceHost + ":" + filename + " " +
                        destHost + ":~";

        Process process = Runtime.getRuntime().exec(command);
        return process.waitFor() == 0;
    } catch (Exception e) {
        return false;
    }
}
```

**Note** : SCP avec `-C` utilise déjà la compression SSH, mais moins efficace que GZIP

---

### Stratégie 3 : Compression adaptative (INTELLIGENTE)

**Principe** : Compresser uniquement si bénéfique

**Algorithme de décision** :
```java
public static boolean shouldCompress(String filename) {
    File file = new File(filename);
    long size = file.length();

    // Seuils basés sur benchmarks
    if (size < 100_000) {
        return false; // < 100 KB : overhead compression > gain transfert
    }

    if (isLocalhost()) {
        return false; // Transfert local : inutile
    }

    if (isMonoSite() && size < 1_000_000) {
        return false; // Mono-site, < 1 MB : gain marginal
    }

    return true; // Multi-site ou gros fichiers : compresser
}
```

**Implémentation** :
```java
public static String transferFileOptimized(String sourceHost,
                                           String destHost,
                                           String filename) {
    if (shouldCompress(filename)) {
        // Compresser puis transférer
        String compressed = compressFile(filename);
        transferFileSCP(sourceHost, destHost, compressed);
        decompressOnRemote(destHost, compressed);
    } else {
        // Transfert direct
        transferFileSCP(sourceHost, destHost, filename);
    }
}
```

---

## 🔧 Implémentation recommandée

### Phase 1 : Support compression GZIP

**Nouvelles classes** :
```
src/utils/FileCompressor.java      # Compression/décompression
src/config/CompressionStrategy.java # Enum : NONE, GZIP, ADAPTIVE
```

**Modifications** :
```
src/utils/FileSplitter.java         # Ajouter splitAndCompress()
src/network/master/MasterCoordinator.java  # Intégrer compression dans transfert
src/config/Configuration.java       # Ajouter config compression
src/scheduler/Main.java             # Ajouter --compression=[none|gzip|adaptive]
```

### Phase 2 : Benchmarking compression

**Métriques à mesurer** :
- Temps de compression
- Temps de transfert (compressé vs non-compressé)
- Temps de décompression
- Taille fichier original vs compressé
- Temps total (end-to-end)

**Ajout dans BenchmarkManager** :
```java
public void recordCompression(String filename,
                              long compressionTime,
                              long originalSize,
                              long compressedSize) {
    // CSV : filename, compression_ms, original_bytes, compressed_bytes, ratio
}
```

---

## 📈 Résultats attendus (estimations)

### Scénario 1 : Fichier texte 10 MB, Grid5000 mono-site

| Méthode | Taille | Temps transfert | Temps compression | Total |
|---------|--------|-----------------|-------------------|-------|
| Sans compression | 10 MB | 2s | 0s | 2s |
| GZIP | 2.5 MB | 0.5s | 0.3s | 0.8s |
| **Gain** | **-75%** | **-75%** | +0.3s | **-60%** |

### Scénario 2 : Fichier texte 100 MB, Grid5000 multi-site

| Méthode | Taille | Temps transfert | Temps compression | Total |
|---------|--------|-----------------|-------------------|-------|
| Sans compression | 100 MB | 20s | 0s | 20s |
| GZIP | 25 MB | 5s | 2s | 7s |
| **Gain** | **-75%** | **-75%** | +2s | **-65%** |

### Scénario 3 : Fichier texte 1 MB, localhost

| Méthode | Taille | Temps transfert | Temps compression | Total |
|---------|--------|-----------------|-------------------|-------|
| Sans compression | 1 MB | 0.05s | 0s | 0.05s |
| GZIP | 0.25 MB | 0.01s | 0.1s | 0.11s |
| **Gain** | **-75%** | **-80%** | +0.1s | **-120%** ❌ |

**Conclusion** : Compression bénéfique pour fichiers > 1 MB sur réseau distant

---

## 🔍 Taux de compression attendus (fichiers texte)

| Type de fichier | Taille originale | Compressé GZIP | Taux |
|----------------|------------------|----------------|------|
| Texte répétitif | 10 MB | 1-2 MB | 80-90% |
| Texte naturel | 10 MB | 2-3 MB | 70-80% |
| Log files | 10 MB | 1.5-2.5 MB | 75-85% |
| Code source | 10 MB | 2.5-3.5 MB | 65-75% |

Pour notre cas (wordcount sur texte) : **taux attendu 70-80%**

---

## 💻 Exemple de code complet

### FileCompressor.java

```java
package utils;

import java.io.*;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

public class FileCompressor {

    private static final int BUFFER_SIZE = 65536; // 64 KB

    /**
     * Compresse un fichier avec GZIP.
     * @param inputFile Fichier à compresser
     * @return Chemin du fichier compressé (.gz)
     */
    public static String compress(String inputFile) throws IOException {
        String outputFile = inputFile + ".gz";
        File input = new File(inputFile);
        long startTime = System.currentTimeMillis();

        try (FileInputStream fis = new FileInputStream(inputFile);
             FileOutputStream fos = new FileOutputStream(outputFile);
             GZIPOutputStream gzos = new GZIPOutputStream(fos, BUFFER_SIZE)) {

            byte[] buffer = new byte[BUFFER_SIZE];
            int len;
            while ((len = fis.read(buffer)) != -1) {
                gzos.write(buffer, 0, len);
            }
        }

        long duration = System.currentTimeMillis() - startTime;
        File output = new File(outputFile);

        double ratio = 100.0 * (1 - (double)output.length() / input.length());
        System.out.printf("[COMPRESS] %s -> %s (%.1f%% reduction) in %d ms%n",
                         inputFile, outputFile, ratio, duration);

        return outputFile;
    }

    /**
     * Décompresse un fichier GZIP.
     * @param inputFile Fichier .gz à décompresser
     * @return Chemin du fichier décompressé
     */
    public static String decompress(String inputFile) throws IOException {
        if (!inputFile.endsWith(".gz")) {
            throw new IllegalArgumentException("File must have .gz extension");
        }

        String outputFile = inputFile.substring(0, inputFile.length() - 3);
        long startTime = System.currentTimeMillis();

        try (FileInputStream fis = new FileInputStream(inputFile);
             GZIPInputStream gzis = new GZIPInputStream(fis, BUFFER_SIZE);
             FileOutputStream fos = new FileOutputStream(outputFile)) {

            byte[] buffer = new byte[BUFFER_SIZE];
            int len;
            while ((len = gzis.read(buffer)) != -1) {
                fos.write(buffer, 0, len);
            }
        }

        long duration = System.currentTimeMillis() - startTime;
        System.out.printf("[DECOMPRESS] %s -> %s in %d ms%n",
                         inputFile, outputFile, duration);

        return outputFile;
    }

    /**
     * Détermine si la compression est bénéfique.
     */
    public static boolean shouldCompress(String filename, boolean isLocal, boolean isMonoSite) {
        File file = new File(filename);
        long size = file.length();

        // Fichiers < 100 KB : overhead > gain
        if (size < 100_000) return false;

        // Transfert local : inutile
        if (isLocal) return false;

        // Mono-site et < 1 MB : gain marginal
        if (isMonoSite && size < 1_000_000) return false;

        return true;
    }
}
```

---

## 🚀 Utilisation

### Sans compression (défaut actuel)
```bash
java -cp bin scheduler.Main "[node1,node2,node3]" --method=SCP
```

### Avec compression GZIP (proposé)
```bash
java -cp bin scheduler.Main "[node1,node2,node3]" --method=SCP --compression=gzip
```

### Avec compression adaptative (proposé)
```bash
java -cp bin scheduler.Main "[node1,node2,node3]" --method=SCP --compression=adaptive
```

### Benchmarking avec/sans compression
```bash
# Sans compression
./scripts/run_benchmarks.sh --workers "[node1,node2]" --method=SCP --compression=none

# Avec compression
./scripts/run_benchmarks.sh --workers "[node1,node2]" --method=SCP --compression=gzip

# Générer les graphes de comparaison
python3 scripts/generate_compression_graphs.py benchmarks/
```

---

## 📊 Métriques à collecter

Pour le benchmarking, mesurer :

1. **Temps de compression** (ms)
2. **Taille originale** (bytes)
3. **Taille compressée** (bytes)
4. **Ratio de compression** (%)
5. **Temps de transfert** (ms)
6. **Temps de décompression** (ms)
7. **Temps total** (compression + transfert + décompression)

**Format CSV** :
```csv
filename,original_size,compressed_size,ratio,compress_ms,transfer_ms,decompress_ms,total_ms
part1.txt,10485760,2621440,75.0,312,498,156,966
```

---

## 🎯 Recommandations

### Pour votre projet actuel

1. **Implémenter** la classe `FileCompressor.java`
2. **Ajouter** option `--compression=[none|gzip|adaptive]` dans `Main.java`
3. **Intégrer** dans `MasterCoordinator.java` pour transferts SCP
4. **Benchmarker** avec et sans compression
5. **Documenter** les résultats dans rapport final

### Stratégie par défaut recommandée

- **Local (localhost)** : Pas de compression
- **Mono-site (Grid5000)** : Compression si fichier > 1 MB
- **Multi-site (Grid5000)** : Toujours compresser

### Arguments pour le professeur

1. **Optimisation réseau** : Démontre compréhension des compromis temps/espace
2. **Architecture modulaire** : Compression optionnelle, configurable
3. **Benchmarking** : Mesures quantitatives des gains de performance
4. **Production-ready** : Stratégie adaptative basée sur contexte

---

## 📚 Références techniques

- **GZIP** : RFC 1952, algorithme DEFLATE
- **Java GZIP** : `java.util.zip.GZIPOutputStream`
- **SCP compression** : Option `-C` (compression SSH native)
- **Benchmarks** : Taux compression texte typique 70-80%

---

## 🔄 Étapes d'implémentation

### Priorité 1 (Essentiel)
- [ ] Créer `FileCompressor.java`
- [ ] Ajouter méthodes `compress()` et `decompress()`
- [ ] Tester compression/décompression localement

### Priorité 2 (Important)
- [ ] Intégrer dans `MasterCoordinator.java`
- [ ] Ajouter option `--compression` dans `Main.java`
- [ ] Modifier workflow transfert fichiers

### Priorité 3 (Bonus)
- [ ] Implémenter stratégie adaptative
- [ ] Ajouter métriques compression dans `BenchmarkManager`
- [ ] Créer graphes comparatifs

### Priorité 4 (Avancé)
- [ ] Tester autres algorithmes (LZ4, Snappy)
- [ ] Compression parallèle (multi-thread)
- [ ] Cache de fichiers compressés

---

**Date** : Novembre 2025
**Projet** : Système distribué de comptage de mots
**Optimisation** : Compression fichiers d'entrée pour réduction temps transfert
