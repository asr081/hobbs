#!/bin/bash
#contact aashish.srivastava@uib.no for any bug reporting, suggestions,improvements
# Script version details
#V4 05june2025:  path updated to 2025 relevant folders , fastqc and adding multiqc in place
# v2: Jan-24: Rita added new paths for 2024 and changed to HiSat2-2.2.1 (using new-summary output)
#v3: July-24: see the path fixes, better log

# Function to display usage information
date=$(date +%d%m%Y-%H%M%S)
start_time=$(date +%s)
usage() {
    echo "Usage: sh $0 [options] <input_directory>"
    echo
    echo "Options:"
    echo "  --help       Display this help message"
    echo
    echo "Example:"
    echo "  sh $0 /path/to/input_directory"
}

# Function to check if a directory exists
check_directory() {
    if [[ ! -d "$1" ]]; then
        echo "Error: Directory $1 does not exist."
        exit 1
    fi
}

# Display help message if --help is passed as an argument
if [[ $1 == "--help" ]]; then
    usage
    exit 0
fi

# Check if input directory is provided and exists
if [[ -z "$1" ]]; then
    echo "Error: No input directory provided."
    usage
    exit 1
fi

INPUT_DIR="$1"
check_directory "$INPUT_DIR"

# Log start of the pipeline
echo "-----------------------------------------------------------"
echo "-------------Welcome to RNA pipeline-----------------------"
echo "-----------------------------------------------------------"
echo "Input to this script is a path which includes paired-end fastq files from human RNA data."
echo "Your input path: $(tput setaf 1) $INPUT_DIR $(tput setaf 7)"
PROJECT_NAME=$(basename "$INPUT_DIR")
# Shortening the name by removing the run suffix
MINI_NAME=$(basename "$INPUT_DIR" | cut -d'_' -f1)
echo "Mini name is $MINI_NAME"
# Picking the run name only
RUN_NAME=$(basename "$INPUT_DIR" | sed "s/^${MINI_NAME}_//")

echo "Your project name: $(tput setaf 1) $PROJECT_NAME $(tput setaf 7)"

echo "Fastq files list:"


cd "$INPUT_DIR" || exit
ls

NUM_FILES=$(ls -1 "$INPUT_DIR"/*.fastq.gz | wc -l)

echo "There are $(tput setaf 1) $NUM_FILES $(tput setaf 7) fastq.gz files in your folder"

# Create output directories
OUTPUT_DIR="/data2/projects_2025/projects_2025/$MINI_NAME/RNA_pipeline_human38/${RUN_NAME}_${date}"
mkdir -p -m 777 "$OUTPUT_DIR/Alignments" "$OUTPUT_DIR/QualityControl" "$OUTPUT_DIR/FeatureCounts"

echo "Analysis output folder: $(tput setaf 1) $OUTPUT_DIR $(tput setaf 7)"

# Initialize log file
LOG_FILE="$OUTPUT_DIR/${MINI_NAME}_RNApipe_log.txt"
{
    echo "Pipeline Log"
    echo "Start Time: $(date)"
    echo "Username: $(whoami)"
    echo "Input Directory: $INPUT_DIR"
    echo "Project Name: $PROJECT_NAME"
    echo "Number of FASTQ files: $NUM_FILES"
    echo "Versions of tools used:"
    echo "All tools below checked to be working oon 05 june 2025"
    echo "FastQC: $(/usr/local/FastQC/fastqc --version | head -n 1)"
    #echo "  HISAT2: $(/usr/local/hisat/hisat2-2.2.1/hisat2 --version | head -n 1)"
    echo " HISAT2: $(/usr/local/hisat/hisat2-2.2.1/hisat2 --version  | head -n 1)"
    echo "  Samtools: $(samtools --version | head -n 1)"
    echo "  featureCounts: $(/usr/local/subread-1.5.2-Linux-x86_64/bin/featureCounts -v)" #add  head -n 1 if it helps#
    #echo "  MultiQC: $(multiqc --version | head -n 1)"
    echo "Input reference file version: GCA_000001405.15_GRCh38_no_alt_analysis_set"
    echo "List of FASTQ files:"
    ls "$INPUT_DIR"/*.fastq.gz | xargs -n 1 basename 
} > "$LOG_FILE"

# Quality check with FastQC
echo "Quality check of fastq files using FastQC."
#UTPUT_DIR/Alignments" || exit

#/usr/local/FastQC/fastqc -t 80 -o "$OUTPUT_DIR/QualityControl/" "$INPUT_DIR"/*.fastq.gz
#echo "FastQC output: $OUTPUT_DIR/QualityControl" >> "$LOG_FILE"

# Alignment using HISAT2
echo "Initiating alignment of fastq files with hisat2-2.2.1, reference genome GRCh38."
cd /usr/local/hisat/hisat2-2.2.1/ || exit
#cd /usr/local/uib-hisat2-2.2.1/ || exit

for SAMPLE in "$INPUT_DIR"/*R1_001.fastq.gz; do
    BASE=$(basename "$SAMPLE" "_R1_001.fastq.gz")
    echo "hisat2-2.2.1 alignment running for sample $BASE"
       ./hisat2 -p 140 -x /data2/01/Hisat_annotation_170523/GCA_000001405.15_GRCh38_no_alt_analysis_set \
        -1 $INPUT_DIR/${BASE}_R1_001.fastq.gz -2 $INPUT_DIR/${BASE}_R2_001.fastq.gz --new-summary \
        --summary-file $OUTPUT_DIR/QualityControl/${BASE}_AlignmentSummary.txt | \
        samtools view -u | samtools sort -@ 140 -m 1G -o $OUTPUT_DIR/Alignments/${BASE}.sorted.bam
#./hisat2 -p 140 -x /data2/01/Hisat_annotation_170523/GCA_000001405.15_GRCh38_no_alt_analysis_set -1 $1/${base}_R1_001.fastq.gz -2 $1/${base}_R2_001.fastq.gz --new-summary --summary-file /data2/projects_2024_1/projects_2024/$project_name/RNA_pipeline/QualityControl/${base}_AlignmentSummary.txt | samtools view -u | samtools sort -@ 140 -m 200G -o /data2/projects_2024_1/projects_2024/$project_name/RNA_pipeline/Alignments/${base}.sorted.bam
done
echo "BAM files location: $OUTPUT_DIR/Alignments" >> "$LOG_FILE"
#<<END
# Indexing BAM files
cd "$OUTPUT_DIR/Alignments" || exit
for BAM in *.bam; do
    echo "Indexing $BAM..."
    samtools index "$BAM"
done

echo "Alignment is ready. The next step is to count reads aligned to the reference transcriptome."

# Feature counting
cd "$OUTPUT_DIR/FeatureCounts" || exit
/usr/local/subread-1.5.2-Linux-x86_64/bin/featureCounts -T 64 -p -t exon -g gene_id -a /data2/01/Hisat_annotation_170523/gencode.v26.chr_patch_hapl_scaff.annotation.gtf \
    -o "$OUTPUT_DIR/FeatureCounts/Counts_genocode_v26_${PROJECT_NAME}.txt" "$OUTPUT_DIR/Alignments"/*.bam

echo "Feature counting is ready. Preparing MultiQC report."

# Generate MultiQC report
cd "$OUTPUT_DIR/QualityControl" || exit
multiqc -f . -o "${PROJECT_NAME}_multiqc_report"
#check 
#sudo docker run --rm multiqc multiqc --help
 sudo docker run --rm -v $OUTPUT_DIR/:/Input -v $OUTPUT_DIR/QualityControl/:/Output ewels/multiqc multiqc /Input -o /Output -n ${PROJECT_NAME}_multiqc_report

echo "MultiQC report location: ${PROJECT_NAME}_multiqc_report" >> "$LOG_FILE"


# Logging completion
end_time=$(date +%s)
run_time=$((end_time - start_time))
{
    echo "End Time: $(date)"
    echo "Pipeline runtime: $((run_time / 3600)) hours $(((run_time / 60) % 60)) minutes $((run_time % 60)) seconds"
} >> "$LOG_FILE"
echo "=/==================================================="
echo  "Complete file structure is as follows"
tree OUTPUT_DIR/
tree OUTPUT_DIR/  >> "$LOG_FILE"


now=$(date +%d-%m-%y-%T)
echo "$now :Pipeline completed"
echo "output of the pipeline are here $OUTPUT_DIR/"
ls $OUTPUT_DIR/



