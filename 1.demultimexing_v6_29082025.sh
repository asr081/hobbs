#!/bin/bash
#aashish.srivastava@uib.com
#v6: Unreleased 29-August-2025 
	#dynamic year in gcf folder /data2/keep_logs/gcf20**
	# checking qc present
	# Usage
	#optional trimming, multiqc, RNAseq pipeline. 
#v4: 05-June-2025: aashish updating paths 2025, add multiqc docker
#v3: 10-Jan-2024: Rita changed 2023 paths to 2024
#v2: 10-Jan-2023
#v1: 01-sept-2022
## Input handling

umask 002  # Ensures group-writable files and directories


usage() {
    echo "
Usage: $(basename $0) [OPTIONS] <runfolder_path>

This script demultiplexes Illumina sequencing runs using bcl2fastq,
copies reports/logs to *keep_logs*, and organizes FASTQ files into project folders.

Arguments:
  runfolder_path       Path to the completed sequencing run directory (must contain SampleSheet.csv)

Options:
  --fastp              Run fastp trimming on FASTQ files after demultiplexing and perform MultiQC 
  --rnaseqhuman        (not in execution yet) Run RNAseq pipeline (2a.RNAhumanpipeline.sh) on FASTQ files
  -h, --help           Show this help message and exit

Notes:
  - Default behavior: demultiplex >> fastqc >> multiqc only (no fastp no RNA pipeline).
  - fastp : demultiplex 

  - Options can be combined:
        $(basename $0) --fastp --multiqc --rnaseqhuman /path/to/runfolder
"
    exit 1
}

# ################ Parse arguments ################
FASTP=false
QC=false
RNAPIPE=false
POSITIONAL_ARGS=() #to store the path

for arg in "$@"; do
  case $arg in
    --fastp) FASTP=true; shift ;;
#    --qc) QC=true; shift ;;
    --rnaseqhuman) RNAPIPE=true; shift ;;
    -h|--help) usage ;;
    -*)
      echo "Unknown option: $arg"
      usage ;;
    *)
      POSITIONAL_ARGS+=("$arg"); shift ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

if [ $# -lt 1 ]; then
    echo "Error: Missing runfolder_path."
    usage
fi

# Input directory
directory=$1

printf "\n\n\n"
echo "********************* You are running bash script named $(basename $0) **************************"
#echo  "This tool demultiplexes your run, saves logs, and optionally runs fastp, multiqc, and rnaseqhuman pipeline."
printf "\n\n\n"

date="$(date +%d%m%Y-%H%M%S)" #this will become a folder name to differentiate between multiple run of this script on same run id. 
flowcell=$(basename $directory)
logdir="/data2/keep_logs/gcf$(date +%Y)/$flowcell/bcl2fastq/$date/" #directory for log
logfile="${logdir}/demultiplexing.log"
bcl2fastq_outdir=/data2/projects_2025/flowcell_2025/${flowcell}/bcl2fastq_output #directory for fastq generated
#BCL2Fastq needs one directory and also generates undetermined.fastq.gz hence this folder above. 
#hence undesired moving from this folder to project folder where we reorganize according to project number. 
#symlink is generated here after fastq is moved out. 
bcl2fastq_outdir_time="$bcl2fastq_outdir/$date"
mkdir -p -m 775 "$logdir"
mkdir -p -m 775 "$bcl2fastq_outdir_time"

echo "Running bcl2fastq..."
/usr/local/bin/bcl2fastq --no-lane-splitting --runfolder-dir "$directory" --output-dir "$bcl2fastq_outdir_time" >> "$logfile" 2>&1
status=$?

project=$(ls $bcl2fastq_outdir_time | grep UiB)

#guarding if project is empty or UiB grep returns nothing. 
if [ -z "$project" ]; then
    echo "[$(date)] No UiB projects found in $bcl2fastq_outdir_time" | tee -a "$logfile"
    exit 1
fi

for var in $project
do
    final_destination=/data2/projects_2025/projects_2025/$var/fastq_files/"$var"_"$flowcell"_"$date"
    mkdir -p -m 777 "$final_destination"
    mkdir -p -m 777 "$final_destination/raw_fastqc"
    mkdir -p -m 777 "$final_destination/trimmed/trimmed_fastqc"

    mv "$bcl2fastq_outdir_time/$var"/* "$final_destination"/
    #Running fastqc on raw fastqc (default option)
    /usr/local/FastQC/fastqc -t 50 -o "$final_destination/raw_fastqc" "$final_destination"/*.fastq.gz
    echo "Moving Fastq files of $var to $final_destination and a symbolic link will be created" | tee -a "$logfile"
    

    ln -s "$final_destination" "$bcl2fastq_outdir_time/$var"



    #_____________________________________________________________
    # ---------- FASTP trimming (if --fastp selected) ----------
    #____________________________________________________________



    if [ "$FASTP" = true ]; then
        echo "[$(date)] Running fastp trimming on $var" | tee -a "$logfile"
        mkdir -p -m 775 "$final_destination/trimmed" #"$final_destination/fastp_reports"
        for r1 in "$final_destination"/*_R1*.fastq.gz; 
        	do
          # Consider moving sample outside loop . 
          sample=$(basename "$r1" | sed 's/_R1.*.fastq.gz//')
		r2="$final_destination/${sample}_R2.fastq.gz"
    if [ ! -f "$r2" ]; then
        echo "[$(date)] Missing R2 file for $sample — skipping trimming." | tee -a "$logfile"
        continue
    fi

		#TRUE RUNNING FASTP on raw # 

            fastp -i "$r1" -I "$r2" \
                  -o "$final_destination/trimmed/${sample}_R1_trimmed.fastq.gz" \
                  -O "$final_destination/trimmed/${sample}_R2_trimmed.fastq.gz" \
                  --detect_adapter_for_pe \
                  --length_required 50 \
                  --qualified_quality_phred 30 \
                  --thread 50 \
                  --html "$final_destination/trimmed/${sample}.fastp.html" \
                  --json "$final_destination/trimmed/${sample}.fastp.json" \
                  >> "$logfile" 2>&1
            done
      	echo "[$(date)] Running FastQC + MultiQC on TRIMMED files for $var ..." | tee -a "$logfile"
 	
    	
    	#TRUE fastqc on trimmed fastq 

    	/usr/local/FastQC/fastqc -t 50 -o "$final_destination/trimmed/trimmed_fastqc" "$final_destination"/trimmed/*.fastq.gz
    	
    	#TRUE: Multiqc on trimmed and raw both

      docker run --rm \
      --user $(id -u):$(id -g) \
        -v "$final_destination:/data" \
      ewels/multiqc:dev multiqc /data -o /data -n ${var}_fastqc_raw-n-trimmed_multiqc_report >> "$logfile" 2>&1
      echo "[$(date)] MultiQC report generated: $final_destination/${var}_fastqc_raw-n-trimmed_multiqc_report" | tee -a "$logfile"
       
    	
    	#________________________________________________________________

    	#FASTP FALSE: Run fastqc and multiqc on only Raw file # No trimming
    	#________________________________________________________________

    else
    echo "[$(date)] Running FastQC + MultiQC on RAW files for $var , No trimming is opted ..." | tee -a "$logfile"

    ## Run MultiQC on raw files
     docker run --rm \
     --user $(id -u):$(id -g) \
        -v "$final_destination:/data" \
        ewels/multiqc:dev multiqc /data -o /data -n ${var}_fastqc_only_raw_multiqc_report >> "$logfile" 2>&1

    echo "[$(date)] MultiQC report generated: $final_destination/${var}_fastqc_only_raw_multiqc_report" | tee -a "$logfile"
fi
done
#

#RNApipeline
# if RNA

## FASTP true/ false loop ends
#==============================================================
	#________________________________
    # ---------- MULTIQC ----------




echo "[$(date)] Pipeline completed." | tee -a "$logfile"
