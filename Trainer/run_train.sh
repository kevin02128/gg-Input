#!/bin/bash
# KyonLM v2 Overnight Training & Core ML Deployment Launcher (run_train.sh)
#
# Usage:
#   ./run_train.sh                  # Default: 9.5 hours overnight training + Core ML deployment
#   ./run_train.sh --hours 10       # Custom duration (10 hours)
#   ./run_train.sh --resume         # Resume from checkpoints/latest.pt

set -euo pipefail

TRAINER_DIR="$(cd "$(dirname "$0")" && pwd)"
GG_DIR="/Users/kevin/development/gg"

cd "$TRAINER_DIR"

echo "============================================================================"
echo "  KyonLM v2 Character-Level Transformer Training Pipeline"
echo "  Trainer Dir : $TRAINER_DIR"
echo "  Target IME  : $GG_DIR"
echo "============================================================================"

if [ ! -f "$TRAINER_DIR/data/vocab.txt" ]; then
    echo "[1/3] Building character vocabulary (vocab.txt)..."
    python3 "$TRAINER_DIR/build_vocab.py" \
        --lexicon "$GG_DIR/Source/Data/data.txt" \
        --output "$TRAINER_DIR/data/vocab.txt" \
        --max-vocab 10500
fi

if [ ! -f "$TRAINER_DIR/corpus/train_sentences.txt" ] || [ ! -f "$TRAINER_DIR/corpus/val_sentences.txt" ]; then
    echo "[2/3] Preparing and normalizing Taiwanese Traditional Chinese corpus..."
    python3 "$TRAINER_DIR/prepare_corpus.py" \
        --gg-root "$GG_DIR" \
        --trainer-root "$TRAINER_DIR"
fi

echo "[3/3] Starting KyonLM training (caffeinate enabled to prevent Mac sleep)..."
caffeinate -i python3 "$TRAINER_DIR/train.py" \
    --gg-root "$GG_DIR" \
    --trainer-root "$TRAINER_DIR" \
    --hours 9.5 \
    "$@"
