#!/usr/bin/env bash

set -euo pipefail
STAGE="${1:?stage required: build | test | train}"

# Every stage runs from the repository root, as the upstream job does:
# unittest discovery and flake8 depend on the working directory.
cd /workspace

case "$STAGE" in

  # push.yml:21-27
  build)
    python -m venv /tmp/venv-build
    export PATH=/tmp/venv-build/bin:$PATH
    python -m pip install --upgrade pip
    pip install --upgrade setuptools
    pip install -e .
    pip install -r requirements.opt.txt
    pip install sacrebleu
    pip install flake8
    if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
    ;;

  # push.yml:30,33
  test)
    flake8 .
    python -m unittest discover
    ;;

  train)
    # push.yml:34-42
    python onmt/bin/build_vocab.py \
      -config data/data.yaml \
      -save_data /tmp/onmt \
      -n_sample 5000 \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      && rm -rf /tmp/sample

    # push.yml:43-52
    python onmt/bin/build_vocab.py \
      -config data/features_data.yaml \
      -save_data /tmp/onmt_feat \
      -src_vocab /tmp/onmt_feat.vocab.src \
      -tgt_vocab /tmp/onmt_feat.vocab.tgt \
      -src_feats_vocab '{"feat0": "/tmp/onmt_feat.vocab.feat0"}' \
      -n_sample -1 \
      && rm -rf /tmp/sample

    # push.yml:53-66
    # The dumped fields are used later when testing tools
    python train.py \
      -config data/data.yaml \
      -save_data /tmp/onmt.train.check \
      -dump_fields \
      -dump_transforms \
      -n_sample 30 \
      -num_workers 0 -bucket_size 1024 \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000

    # push.yml:67-81
    python train.py \
      -config data/data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -hidden_size 2 \
      -num_workers 0 -bucket_size 1024 \
      -batch_size 10 \
      -word_vec_size 5 \
      -report_every 5\
      -hidden_size 10 \
      -train_steps 10

    # push.yml:82-97
    python train.py \
      -config data/data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -hidden_size 2 \
      -num_workers 0 -bucket_size 1024 \
      -batch_size 10 \
      -word_vec_size 5 \
      -report_every 5 \
      -hidden_size 10 \
      -train_steps 10 \
      -copy_attn

    # push.yml:98-110
    python train.py \
      -config data/data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -hidden_size 2 -batch_size 10 \
      -num_workers 0 -bucket_size 1024 \
      -word_vec_size 5 -report_every 5        \
      -coverage_attn true -lambda_coverage 0.1 \
      -hidden_size 10 -train_steps 10

    # push.yml:111-135
    python train.py \
      -config data/align_data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -max_generator_batches 0 \
      -encoder_type transformer \
      -decoder_type transformer \
      -layers 4 \
      -word_vec_size 16 \
      -hidden_size 16 \
      -num_workers 0 -bucket_size 1024 \
      -heads 2 \
      -transformer_ff 64 \
      -lambda_align 0.05 \
      -alignment_layer 2 \
      -alignment_heads 0 \
      -dropout_steps 0 3 7 \
      -dropout 0.3 0.2 0.1 \
      -attention_dropout 0.2 0.1 0.1 \
      -report_every 5 \
      -train_steps 10

    # push.yml:136-151
    python train.py \
        -config data/lm_data.yaml \
        -src_vocab /tmp/onmt.vocab.src \
        -tgt_vocab /tmp/onmt.vocab.src \
        -model_task lm \
        -encoder_type transformer_lm \
        -decoder_type transformer_lm \
        -src_vocab_size 1000 \
        -tgt_vocab_size 1000 \
        -num_workers 0 -bucket_size 1024 \
        -dec_layers 2 -batch_size 10 \
        -heads 4 -transformer_ff 64 \
        -word_vec_size 16 -report_every 5 \
        -hidden_size 16 -train_steps 10

    # push.yml:152-168
    python train.py \
      -config data/lm_data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.src \
      -model_task lm \
      -encoder_type transformer_lm \
      -decoder_type transformer_lm \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -num_workers 0 -bucket_size 1024 \
      -dec_layers 2 -batch_size 10 \
      -heads 4 -transformer_ff 64 \
      -word_vec_size 16 -report_every 5        \
      -hidden_size 16 -train_steps 10 \
      -copy_attn

    # push.yml:169-190
    python train.py \
      -config data/ggnn_data.yaml \
      -src_seq_length 1000 \
      -tgt_seq_length 30 \
      -encoder_type ggnn \
      -layers 2 \
      -decoder_type rnn \
      -hidden_size 256 \
      -learning_rate 0.1 \
      -learning_rate_decay 0.8 \
      -global_attention general \
      -batch_size 32 \
      -word_vec_size 256 \
      -bridge \
      -num_workers 0 -bucket_size 1024 \
      -train_steps 10 \
      -n_edge_types 9 \
      -state_dim 256 \
      -n_steps 10 \
      -n_node 64

    # push.yml:191-204
    python onmt/bin/train.py \
      -config data/features_data.yaml \
      -src_vocab /tmp/onmt_feat.vocab.src \
      -tgt_vocab /tmp/onmt_feat.vocab.tgt \
      -src_feats_vocab '{"feat0": "/tmp/onmt_feat.vocab.feat0"}' \
      -src_vocab_size 1000 -tgt_vocab_size 1000 \
      -hidden_size 2 -batch_size 10 \
      -num_workers 0 -bucket_size 1024 \
      -word_vec_size 5 -hidden_size 10 \
      -report_every 5 -train_steps 10 \
      -save_model /tmp/onmt.model \
      -save_checkpoint_steps 10

    # push.yml:335-368
    python train.py \
      -config data/data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -hidden_size 2 \
      -batch_size 10 \
      -word_vec_size 5 \
      -report_every 5\
      -hidden_size 10 \
      -num_workers 0 -bucket_size 1024 \
      -train_steps 10 \
      -save_model /tmp/onmt.model \
      -save_checkpoint_steps 10
    sed -i '1s/^/new_tok\t100000000\n/' /tmp/onmt.vocab.src
    python train.py \
      -config data/data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.tgt \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -hidden_size 2 \
      -batch_size 10 \
      -word_vec_size 5 \
      -report_every 5\
      -hidden_size 10 \
      -train_steps 20 \
      -num_workers 0 -bucket_size 1024 \
      -update_vocab \
      -reset_optim "states" \
      -train_from /tmp/onmt.model_step_10.pt

    # push.yml:369-403
    python train.py \
      -config data/lm_data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.src \
      -model_task lm \
      -encoder_type transformer_lm \
      -decoder_type transformer_lm \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -dec_layers 2 -batch_size 10 \
      -heads 4 -transformer_ff 64 \
      -num_workers 0 -bucket_size 1024 \
      -word_vec_size 16 -report_every 5 \
      -save_model /tmp/lm.onmt.model \
      -save_checkpoint_steps 10 \
      -hidden_size 16 -train_steps 10
    sed -i '1s/^/new_tok2\t100000000\n/' /tmp/onmt.vocab.src
    python train.py \
      -config data/lm_data.yaml \
      -src_vocab /tmp/onmt.vocab.src \
      -tgt_vocab /tmp/onmt.vocab.src \
      -model_task lm \
      -encoder_type transformer_lm \
      -decoder_type transformer_lm \
      -src_vocab_size 1000 \
      -tgt_vocab_size 1000 \
      -num_workers 0 -bucket_size 1024 \
      -dec_layers 2 -batch_size 10 \
      -heads 4 -transformer_ff 64 \
      -word_vec_size 16 -report_every 5 \
      -hidden_size 16  -train_steps 20 \
      -update_vocab -reset_optim "states" \
      -train_from /tmp/lm.onmt.model_step_10.pt
    ;;

  *)
    echo "Unknown stage: $STAGE" >&2
    exit 1
    ;;
esac
