#!/bin/bash

script_name=`basename $0`
script_dir=`dirname $0`

source "${script_dir}/commonfunctions.sh"

version="???"
waitinterval="1"

if [ -f "$script_dir/VERSION" ] ; then
    version=`cat $script_dir/VERSION`
fi

function usage()
{
    echo "usage: $script_name [-h]
                      predictdir

              Version: $version

              Runs StartPostprocessing.m and Merge_LargeData.m
              as packages become available to process.
              This script uses predict.config 
              file to obtain location of trained model 
              and image data

positional arguments:
  predictdir           Predict directory generated by
                       runprediction.sh

optional arguments:
  -h, --help           show this help message and exit

  --waitinterval       Number of seconds to wait between checking
                       for number of completed packages 
                       (default $waitinterval)

    " 1>&2;
    exit 1;
}

TEMP=`getopt -o h --long "help,waitinterval:" -n '$0' -- "$@"`
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h ) usage ;;
        --help ) usage ;;
        --waitinterval ) waitinterval=$2 ; shift 2 ;;
        --) shift ; break ;;
    esac
done

if [ $# -ne 1 ] ; then
  usage
fi

out_dir=$1

echo ""

predict_config="$out_dir/predict.config"

parse_predict_config "$predict_config"

if [ $? != 0 ] ; then
    fatal_error "$out_dir" "ERROR parsing $predict_config" 2
fi

echo "Running Postprocess"
echo ""

echo "Trained Model Dir: $trained_model_dir"
echo "Image Dir: $img_dir"
echo "Models: $model_list"
echo "Speed: $aug_speed"
echo ""

package_proc_info="$out_dir/augimages/package_processing_info.txt"

if [ ! -s "$package_proc_info" ] ; then
    fatal_error "$out_dir" "ERROR $package_proc_info not found" 7
fi

parse_package_processing_info "$package_proc_info"

space_sep_models=$(get_models_as_space_separated_list "$model_list")

for model_name in `echo $space_sep_models` ; do
    if [ -f "$out_dir/$model_name/DONE" ] ; then
        echo "Found $out_dir/$model_name/DONE Prediction on model completed. Skipping..."
        continue
    fi 
    let cntr=1
    for CUR_PKG in `seq -w 001 $num_pkgs` ; do
        for CUR_Z in `seq -w 01 $num_zstacks` ; do
            package_name=$(get_package_name "$CUR_PKG" "$CUR_Z")
            Z="$out_dir/augimages/$model_name/$package_name"
            out_pkg="$out_dir/$model_name/$package_name"
            if [ -f "$out_pkg/DONE" ] ; then
                echo "  Found $out_pkg/DONE Prediction completed. Skipping..."
                continue
            fi
            echo "For model $model_name postprocessing $package_name $cntr of $tot_pkgs"
            echo "Waiting for $out_pkg to finish processing"
            res=$(wait_for_predict_to_finish_on_package "$out_dir" "$out_pkg" "$waitinterval")
            if [ "$res" == "killed" ] ; then
                echo "KILL.REQUEST file found. Exiting"
                exit 1
            fi

            echo "Running StartPostprocessing.m on $out_pkg"
            StartPostprocessing.m "$out_pkg"
            ecode=$?
            if [ $ecode != 0 ] ; then
                fatal_error "$out_dir" "ERROR non-zero exit code ($ecode) from running StartPostprocessing.m" 7
            fi
            echo "0" > "$out_pkg/DONE"
            echo "Removing $Z"
            /bin/rm -rf "$Z"
            let cntr+=1
        done
    done
    Merge_LargeData.m "$out_dir/$model_name"
    ecode=$?
    if [ $ecode != 0 ] ; then
        fatal_error "$out_dir" "ERROR non-zero exit code ($ecode) from running Merge_LargeData.m" 8
    fi
    echo "Removing Pkg_* folders"
    /bin/rm -rf $out_dir/$model_name/Pkg_*
done

echo ""
echo "Postprocessing has completed."
echo ""
