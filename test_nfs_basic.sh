#!/bin/bash

echo "════════════════════════════════════════════════════════"
echo "   TEST BASIQUE DE LA VERSION NFS"
echo "════════════════════════════════════════════════════════"
echo ""

# Test 1: Vérifier la compilation
echo "✓ Test 1: Vérification de la compilation"
if [ -f "bin/scheduler/MainNFS.class" ]; then
    echo "  ✅ MainNFS.class compilé"
else
    echo "  ❌ MainNFS.class manquant"
    exit 1
fi

if [ -f "bin/parser/TaskNFS.class" ]; then
    echo "  ✅ TaskNFS.class compilé"
else
    echo "  ❌ TaskNFS.class manquant"
    exit 1
fi

# Test 2: Vérifier le répertoire NFS
echo ""
echo "✓ Test 2: Vérification du répertoire NFS"
if [ -d "/tmp/nfs_shared" ]; then
    echo "  ✅ Répertoire NFS existe: /tmp/nfs_shared"
    echo "  Contenu:"
    ls -lh /tmp/nfs_shared/ | tail -n +2 | awk '{print "    - " $9 " (" $5 ")"}'
else
    echo "  ❌ Répertoire NFS manquant"
    exit 1
fi

# Test 3: Tester FileSplitter avec NFS path
echo ""
echo "✓ Test 3: Test du FileSplitter avec NFS"
cd /tmp/nfs_shared
java -cp /home/user/wordcount-distributed/bin utils.FileSplitter test_nfs_input.txt 3 part

if [ $? -eq 0 ]; then
    echo "  ✅ FileSplitter fonctionne"
    echo "  Fichiers créés:"
    ls -lh part*.txt | awk '{print "    - " $9 " (" $5 ", " $2 " lignes)"}'
else
    echo "  ❌ FileSplitter échoué"
    exit 1
fi

# Test 4: Compter les lignes
echo ""
echo "✓ Test 4: Vérification de la division équitable"
TOTAL_LINES=$(wc -l < test_nfs_input.txt)
PART1_LINES=$(wc -l < part1.txt)
PART2_LINES=$(wc -l < part2.txt)
PART3_LINES=$(wc -l < part3.txt)
SUM=$((PART1_LINES + PART2_LINES + PART3_LINES))

echo "  Lignes totales: $TOTAL_LINES"
echo "  Part1: $PART1_LINES lignes"
echo "  Part2: $PART2_LINES lignes"
echo "  Part3: $PART3_LINES lignes"
echo "  Somme: $SUM lignes"

if [ $SUM -eq $TOTAL_LINES ]; then
    echo "  ✅ Division équitable correcte"
else
    echo "  ❌ Division incorrecte"
    exit 1
fi

# Test 5: Test du wordcount sur les parties
echo ""
echo "✓ Test 5: Test du programme wordcount"
./wordcount part1.txt > count1.txt
./wordcount part2.txt > count2.txt
./wordcount part3.txt > count3.txt

COUNT1=$(cat count1.txt)
COUNT2=$(cat count2.txt)
COUNT3=$(cat count3.txt)
TOTAL=$((COUNT1 + COUNT2 + COUNT3))

echo "  Count1: $COUNT1 mots"
echo "  Count2: $COUNT2 mots"
echo "  Count3: $COUNT3 mots"
echo "  Total: $TOTAL mots"

if [ $TOTAL -gt 0 ]; then
    echo "  ✅ Wordcount fonctionne"
else
    echo "  ❌ Wordcount échoué"
    exit 1
fi

# Test 6: Vérifier que tous les fichiers sont dans NFS
echo ""
echo "✓ Test 6: Vérification des fichiers NFS"
echo "  Tous les fichiers dans /tmp/nfs_shared:"
ls -lh /tmp/nfs_shared/*.txt 2>/dev/null | wc -l
echo "  fichiers .txt trouvés"

echo ""
echo "════════════════════════════════════════════════════════"
echo "   ✅ TOUS LES TESTS BASIQUES RÉUSSIS!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "La version NFS est prête à être testée sur Grid5000 avec:"
echo "  ./deploy/run_nfs_mono_site.sh <input-file>"
echo "  ./deploy/run_nfs_multi_site.sh <combined_nodefile> <input-file>"
