#!/bin/bash

# Input arguments
runfolder="$1"
outdir="$2"
flowcell="$3"
year=$(date +%Y)
logdir="/data2/keep_logs/gcf${year}/${flowcell}/bcl2fastq"
logfile="${logdir}/run_$(date +%Y%m%d_%H%M%S).log"

# Run bcl2fastq and log output
echo "[$(date)] Starting bcl2fastq..." | tee -a "$logfile"
/usr/local/bin/bcl2fastq --no-lane-splitting --runfolder-dir "$runfolder" --output-dir "$outdir" >> "$logfile" 2>&1
status=$?

# Check for key output files
conversion_stats="${outdir}/ConversionStats.xml"
demux_stats="${outdir}/DemultiplexingStats.xml"

if [ $status -eq 0 ] && [ -f "$conversion_stats" ] && [ -f "$demux_stats" ]; then
    echo "[$(date)] bcl2fastq finished successfully. Output files are present." | tee -a "$logfile"
else
    echo "[$(date)] bcl2fastq may have failed. Check log and output directory." | tee -a "$logfile"
    if [ $status -ne 0 ]; then
        echo "Exit status: $status (non-zero indicates failure)" | tee -a "$logfile"
    fi
    if [ ! -f "$conversion_stats" ]; then
        echo "Missing: ConversionStats.xml" | tee -a "$logfile"
    fi
    if [ ! -f "$demux_stats" ]; then
        echo "Missing: DemultiplexingStats.xml" | tee -a "$logfile"
    fi
fi
