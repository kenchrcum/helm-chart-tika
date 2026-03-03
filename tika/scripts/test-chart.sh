#!/bin/bash
# test-chart.sh — Local testing script for the Apache Tika Helm chart
# Run from the repository root: bash tika/scripts/test-chart.sh
# Or from the tika/ directory: bash scripts/test-chart.sh

set -euo pipefail

# Resolve chart directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Testing Helm chart at: $CHART_DIR"
echo "================================================"

# Test 1: Default configuration
echo ""
echo "[1/6] Default template rendering..."
helm template test "$CHART_DIR" > /dev/null
echo "      ✓ Default template renders"

# Test 2: Minimal image (tika.fullImage=false)
echo ""
echo "[2/6] Minimal image template rendering..."
helm template test "$CHART_DIR" --set tika.fullImage=false > /dev/null
echo "      ✓ Minimal image template renders"

# Test 3: Custom tika-config.xml
echo ""
echo "[3/6] Custom config template rendering..."
helm template test "$CHART_DIR" --set tika.config="<properties></properties>" > /dev/null
echo "      ✓ Custom config template renders"

# Test 4: CI default values file
echo ""
echo "[4/6] CI default values file..."
helm template test "$CHART_DIR" -f "$CHART_DIR/tests/ci-default.yaml" > /dev/null
echo "      ✓ ci-default renders"

# Test 4b: CI minimal image values file
helm template test "$CHART_DIR" -f "$CHART_DIR/tests/ci-minimal-image.yaml" > /dev/null
echo "      ✓ ci-minimal-image renders"

# Test 4c: CI custom config values file
helm template test "$CHART_DIR" -f "$CHART_DIR/tests/ci-custom-config.yaml" > /dev/null
echo "      ✓ ci-custom-config renders"

# Test 5: Full feature set (all production features enabled)
echo ""
echo "[5/6] Full feature set values file..."
helm template test "$CHART_DIR" -f "$CHART_DIR/tests/ci-full-features.yaml" > /dev/null
echo "      ✓ ci-full-features renders"

# Test 6: Helm lint
echo ""
echo "[6/6] Helm lint validation..."
helm lint "$CHART_DIR" > /dev/null 2>&1
echo "      ✓ Chart passes helm lint"

echo ""
echo "================================================"
echo "All tests passed! ✓"
