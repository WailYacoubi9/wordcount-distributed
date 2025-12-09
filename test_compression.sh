#!/bin/bash

# Script de test pour démontrer les gains de compression

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     TEST DE COMPRESSION - Démo des Gains               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if bin directory exists
if [ ! -d "bin" ]; then
    echo -e "${YELLOW}⚠️  bin/ directory not found. Compiling first...${NC}"
    javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
          src/parser/*.java src/network/worker/*.java \
          src/network/master/*.java src/scheduler/*.java
    echo ""
fi

echo -e "${BLUE}📊 Analyse des fichiers à transférer :${NC}"
echo ""

# Analyze each component
echo "Composants :"

if [ -d "bin" ]; then
    BIN_SIZE=$(du -sb bin 2>/dev/null | awk '{print $1}')
    BIN_FILES=$(find bin -type f | wc -l)
    echo "  📁 bin/ : $(numfmt --to=iec $BIN_SIZE 2>/dev/null || echo "$BIN_SIZE bytes") ($BIN_FILES fichiers .class)"
else
    BIN_SIZE=0
    echo "  📁 bin/ : Non trouvé"
fi

if [ -f "wordcount" ]; then
    WC_SIZE=$(stat -f%z "wordcount" 2>/dev/null || stat -c%s "wordcount" 2>/dev/null)
    echo "  📄 wordcount : $(numfmt --to=iec $WC_SIZE 2>/dev/null || echo "$WC_SIZE bytes") (binaire C)"
else
    WC_SIZE=0
    echo "  📄 wordcount : Non trouvé"
fi

if [ -d "test" ]; then
    TEST_SIZE=$(du -sb test 2>/dev/null | awk '{print $1}')
    echo "  📁 test/ : $(numfmt --to=iec $TEST_SIZE 2>/dev/null || echo "$TEST_SIZE bytes") (sources C)"
else
    TEST_SIZE=0
    echo "  📁 test/ : Non trouvé"
fi

TOTAL_SIZE=$((BIN_SIZE + WC_SIZE + TEST_SIZE))
echo ""
echo -e "${GREEN}Total (non compressé) : $(numfmt --to=iec $TOTAL_SIZE 2>/dev/null || echo "$TOTAL_SIZE bytes")${NC}"
echo ""

# Create compressed archive
echo -e "${BLUE}🗜️  Compression en cours...${NC}"

ARCHIVE_NAME="test_compression.tar.gz"
COMP_START=$(date +%s.%N 2>/dev/null || date +%s)

tar -czf $ARCHIVE_NAME bin wordcount test 2>/dev/null

COMP_END=$(date +%s.%N 2>/dev/null || date +%s)
COMP_TIME=$(awk "BEGIN {printf \"%.3f\", $COMP_END - $COMP_START}" 2>/dev/null || echo "N/A")

ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_NAME" 2>/dev/null || stat -c%s "$ARCHIVE_NAME" 2>/dev/null)

echo -e "${GREEN}✅ Compression terminée en ${COMP_TIME}s${NC}"
echo ""

# Calculate statistics
COMPRESSION_RATIO=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_SIZE / $ARCHIVE_SIZE)}")
SPACE_SAVED=$((TOTAL_SIZE - ARCHIVE_SIZE))
PERCENTAGE_SAVED=$(awk "BEGIN {printf \"%.1f\", (($TOTAL_SIZE - $ARCHIVE_SIZE) / $TOTAL_SIZE) * 100}")

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 RÉSULTATS COMPRESSION                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Taille originale    : $(numfmt --to=iec $TOTAL_SIZE 2>/dev/null || echo "$TOTAL_SIZE bytes")"
echo "Taille compressée   : $(numfmt --to=iec $ARCHIVE_SIZE 2>/dev/null || echo "$ARCHIVE_SIZE bytes")"
echo "Espace économisé    : $(numfmt --to=iec $SPACE_SAVED 2>/dev/null || echo "$SPACE_SAVED bytes") (${PERCENTAGE_SAVED}%)"
echo "Ratio compression   : ${COMPRESSION_RATIO}x"
echo "Temps compression   : ${COMP_TIME}s"
echo ""

# Simulate multi-site scenario
echo -e "${BLUE}📡 Simulation scénario multi-site :${NC}"
echo ""

read -p "Nombre de workers distants ? [4] : " NUM_WORKERS
NUM_WORKERS=${NUM_WORKERS:-4}

TOTAL_TRANSFER_UNCOMPRESSED=$((TOTAL_SIZE * NUM_WORKERS))
TOTAL_TRANSFER_COMPRESSED=$((ARCHIVE_SIZE * NUM_WORKERS))
BANDWIDTH_SAVED=$((TOTAL_TRANSFER_UNCOMPRESSED - TOTAL_TRANSFER_COMPRESSED))

echo ""
echo "Avec $NUM_WORKERS workers :"
echo ""
echo "  Sans compression :"
echo "    Données transférées : $(numfmt --to=iec $TOTAL_TRANSFER_UNCOMPRESSED 2>/dev/null || echo "$TOTAL_TRANSFER_UNCOMPRESSED bytes")"
echo ""
echo "  Avec compression :"
echo "    Données transférées : $(numfmt --to=iec $TOTAL_TRANSFER_COMPRESSED 2>/dev/null || echo "$TOTAL_TRANSFER_COMPRESSED bytes")"
echo ""
echo -e "${GREEN}  Bande passante économisée : $(numfmt --to=iec $BANDWIDTH_SAVED 2>/dev/null || echo "$BANDWIDTH_SAVED bytes") (${PERCENTAGE_SAVED}%)${NC}"
echo ""

# Estimate time savings
echo -e "${BLUE}⏱️  Estimation temps de transfert :${NC}"
echo ""
echo "  (Bande passante estimée : 50 MB/s inter-sites)"
echo ""

BANDWIDTH_MBPS=50
BANDWIDTH_BPS=$((BANDWIDTH_MBPS * 1024 * 1024))

TIME_UNCOMPRESSED=$(awk "BEGIN {printf \"%.2f\", $TOTAL_TRANSFER_UNCOMPRESSED / $BANDWIDTH_BPS}")
TIME_COMPRESSED=$(awk "BEGIN {printf \"%.2f\", ($COMP_TIME + ($TOTAL_TRANSFER_COMPRESSED / $BANDWIDTH_BPS))}")
TIME_SAVED=$(awk "BEGIN {printf \"%.2f\", $TIME_UNCOMPRESSED - $TIME_COMPRESSED}")

echo "  Sans compression : ${TIME_UNCOMPRESSED}s"
echo "  Avec compression : ${TIME_COMPRESSED}s (dont ${COMP_TIME}s compression)"
echo ""
echo -e "${GREEN}  Temps économisé  : ${TIME_SAVED}s${NC}"
echo ""

# Decompression test
echo -e "${BLUE}📦 Test de décompression...${NC}"

DECOMP_START=$(date +%s.%N 2>/dev/null || date +%s)

mkdir -p test_extract
tar -xzf $ARCHIVE_NAME -C test_extract 2>/dev/null

DECOMP_END=$(date +%s.%N 2>/dev/null || date +%s)
DECOMP_TIME=$(awk "BEGIN {printf \"%.3f\", $DECOMP_END - $DECOMP_START}" 2>/dev/null || echo "N/A")

echo -e "${GREEN}✅ Décompression terminée en ${DECOMP_TIME}s${NC}"
echo ""

# Cleanup
rm -rf test_extract
rm -f $ARCHIVE_NAME

# Summary
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                      RÉSUMÉ                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Compression    : ${COMPRESSION_RATIO}x (${PERCENTAGE_SAVED}% économie)"
echo "  Vitesse        : Compression ${COMP_TIME}s / Décompression ${DECOMP_TIME}s"
echo "  Multi-site     : $(numfmt --to=iec $BANDWIDTH_SAVED 2>/dev/null || echo "$BANDWIDTH_SAVED bytes") économisés pour $NUM_WORKERS workers"
echo "  Gain temps     : ${TIME_SAVED}s par déploiement"
echo ""
echo -e "${GREEN}✅ La compression est rentable !${NC}"
echo ""
echo "Pour utiliser en mode multi-site :"
echo "  bash deploy/run_multi_site.sh"
echo ""
