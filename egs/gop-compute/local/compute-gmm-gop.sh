#!/bin/bash
# Copyright 2016  Author: Junbo Zhang
# Apache 2.0

# Computes GOP.


# Begin configuration section.
nj=1
cmd=run.pl
# Begin configuration.
# End configuration options.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh # source the path.
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "usage: local/compute-gmm-gop.sh <data-dir> <lang-dir> <src-dir> <ali-dir> <gop-dir>"
   echo "e.g.:  local/compute-gmm-gop.sh data/train data/lang exp/tri1 exp/tri1_ali exp/tri1_gop"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>                           # config containing options"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data=$1
lang=$2
srcdir=$3
alidir=$4
dir=$5

for f in $data/text $lang/oov.int $srcdir/tree $srcdir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1;
done

oov=`cat $lang/oov.int` || exit 1;
mkdir -p $dir/log
echo $nj > $dir/num_jobs
sdata=$data/split$nj
splice_opts=`cat $srcdir/splice_opts 2>/dev/null` # frame-splicing options.
cp $srcdir/splice_opts $dir 2>/dev/null # frame-splicing options.
cmvn_opts=`cat $srcdir/cmvn_opts 2>/dev/null`
delta_opts=`cat $srcdir/delta_opts 2>/dev/null`

[[ -d $sdata && $data/feats.scp -ot $sdata ]] || split_data.sh $data $nj || exit 1;

if [ -f $srcdir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
echo "$0: feature type is $feat_type"

case $feat_type in
  delta) feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas $delta_opts ark:- ark:- |";;
  lda) feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $srcdir/final.mat ark:- ark:- |"
    cp $srcdir/final.mat $srcdir/full.mat $dir
   ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac

echo "$0: computing GOP in $data using model from $srcdir, putting results in $dir"

mdl=$srcdir/final.mdl
tra="ark:utils/sym2int.pl --map-oov $oov -f 2- $lang/words.txt $sdata/JOB/text|";
$cmd JOB=1:$nj $dir/log/gop.JOB.log \
  compute-gmm-gop $mdl "$feats" "ark:gunzip -c $alidir/ali.JOB.gz|" "$dir/gop.JOB" || exit 1;

# Convenience for debug
# gunzip exp/eval_ali/ali.1.gz
# apply-cmvn --utt2spk=ark:data/eval/split1/1/utt2spk scp:data/eval/split1/1/cmvn.scp scp:data/eval/split1/1/feats.scp ark:- | add-deltas ark:- ark,t:data/eval/feats.1.ark.txt
# compute-gmm-gop exp/tri1/final.mdl ark,t:data/eval/feats.1.ark.txt ark,t:exp/eval_ali/ali.1 exp/eval_gop/gop.1

echo "$0: done computing GOP."
