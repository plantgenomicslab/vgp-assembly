#!/bin/bash
# scaff10x 0.0.1
# Generated by dx-app-wizard.
#
# Basic execution pattern: Your app will run on a single machine from
# beginning to end.
#
# Your job's input variables (if any) will be loaded as environment
# variables before this script runs.  Any array inputs will be loaded
# as bash arrays.
#
# Any code outside of main() (or any entry point you may add) is
# ALWAYS executed, followed by running the entry point itself.
#
# See https://wiki.dnanexus.com/Developer-Portal for tutorials on how
# to modify this file.

set -x -e -o pipefail 
MAX_NUM_SUBJOBS=50

splitter() { #NOT USED IN V4.0

    echo "Value of assemble_genome_fastagz: '$assemble_genome_fastagz'"
    echo "Value of scaff_R1_fastqgz: '${scaff_R1_fastqgz[@]}'"
    echo "Value of scaff_R2_fastqgz: '${scaff_R2_fastqgz[@]}'"
    echo "Value of mapper_choice: '$mapper_choice'"
    echo "Value of mapper_file: '$mapper_file'"
    echo "Value of alignment_option: '$alignment_option'"
    echo "Value of break10x_option: '$break10x_option'"

    # sanity check inputs
    if [ "${#scaff_R1_fastqgz[@]}" != "${#scaff_R2_fastqgz[@]}" ]; then
        dx-jobutil-report-error "number of forward and reverse reads are not equal" AppError
    fi

    # if raw, break input reads into chunks and run remove_bcs() subjobs
    # if not raw, just run run_scaff10x()
    scaff10x_inputs=""
    if [[ "$is_raw" == 'true' ]]; then
        # compute total size of inputs
        total_input_size=0
        for i in ${!scaff_R1_fastqgz[@]}; do
            input1_size=$(dx describe "${scaff_R1_fastqgz[$i]}" --json | jq -r .size)
            input2_size=$(dx describe "${scaff_R2_fastqgz[$i]}" --json | jq -r .size)
            total_input_size=$((total_input_size + input1_size + input2_size))
        done

        # convert total size to GiB
        echo "${total_input_size}/1024/1024/1024"
        total_input_size=$(echo "${total_input_size}/1024/1024/1024" | bc )

        # create chunks
        # Here we attempt to split into roughly 10GiB chunk size per subjob.
        num_chunks=$(echo "(${total_input_size}/10 + 0.5)/1"|bc )
        if [ "$num_chunks" -gt "$MAX_NUM_SUBJOBS" ]; then
            num_chunks=$MAX_NUM_SUBJOBS
        elif [ "$num_chunks" -lt "1" ]; then
            num_chunks=1
        fi

        num_files_per_chunk=$(echo "(${#scaff_R1_fastqgz[@]}/${num_chunks} + 0.5)/1" | bc )
        if [ "$num_files_per_chunk" -lt "1" ]; then
            num_files_per_chunk=1
        fi

        if [ "$num_chunks" -lt "2" ]; then
            slices=( 0 ${#scaff_R1_fastqgz[@]} )
        elif [ $(( ${#scaff_R1_fastqgz[@]} % ${num_files_per_chunk} )) -eq "0" ]; then
            slices=( $(seq 0 ${num_files_per_chunk} ${#scaff_R1_fastqgz[@]}) )
        else
            slices=( $(seq 0 ${num_files_per_chunk} ${#scaff_R1_fastqgz[@]}) ${#scaff_R1_fastqgz[@]} )
        fi

        # now submit a subjob for each slice
        for n in ${!slices[@]}; do
           # make sure we don't only use the last slice as an endpoint
           if [[ ${slices[$n+1]} == "" ]]; then continue; fi

           subjob_inputs=""
           for (( i=$n; i<${slices[$n+1]}; i++ )); do
               r1_input=$(dx-jobutil-parse-link "${scaff_R1_fastqgz[$i]}")
               r2_input=$(dx-jobutil-parse-link "${scaff_R2_fastqgz[$i]}")
               subjob_inputs="$subjob_inputs -iscaff_R1_fastqgz=$r1_input -iscaff_R2_fastqgz=$r2_input"
           done
           remove_bcs_job=$(dx-jobutil-new-job remove_bcs $subjob_inputs )
           scaff10x_inputs="$scaff10x_inputs -iscaff_R1_fastqgz=$remove_bcs_job:read_bc1 -iscaff_R2_fastqgz=$remove_bcs_job:read_bc2"
        done
    else
        for i in ${!scaff_R1_fastqgz[@]}; do
            r1_input=$(dx-jobutil-parse-link "${scaff_R1_fastqgz[$i]}")
            r2_input=$(dx-jobutil-parse-link "${scaff_R2_fastqgz[$i]}")
            scaff10x_inputs="$scaff10x_inputs -iscaff_R1_fastqgz=$r1_input -iscaff_R2_fastqgz=$r2_input"
        done
    fi
 
    # now run the scaff10x job
    assemble_genome_fastagz=$(dx-jobutil-parse-link "$assemble_genome_fastagz")
    if [[ -n "$mapping_file" ]]; then
        mapping_file=$(dx-jobutil-parse-link "$mapping_file")
        scaff10x_inputs="$scaff10x_inputs -imapping_file=$mapping_file"
    fi

    if [[ $output_prefix != "" ]]; then
        scaff10x_inputs="$scaff10x_inputs -ioutput_prefix=$output_prefix"
    fi
    
    scaff10x_job=$( dx-jobutil-new-job run_scaff10x $scaff10x_inputs \
        -iassemble_genome_fastagz=$assemble_genome_fastagz \
        -imapper_choice=$mapper_choice -ialignment_option="${alignment_option}" \
        -ibreak10x_option="${break10x_option}" )
   
    # link outputs
    dx-jobutil-add-output read_bc1 "$scaff10x_job":read_bc1 --class=jobref
    dx-jobutil-add-output read_bc2 "$scaff10x_job":read_bc2 --class=jobref
    dx-jobutil-add-output scaffold "$scaff10x_job":scaffold --class=jobref
    dx-jobutil-add-output other_outputs "$scaff10x_job":other_outputs --class=jobref
    
    if [[ "$disable_break10x" == 'false' ]]; then
        dx-jobutil-add-output breakpoint "$scaff10x_job":breakpoint --class=jobref
        dx-jobutil-add-output breakpoint_name "$scaff10x_job":breakpoint_name --class=jobref
    fi
}

remove_bcs() { #NOT USED IN V4.0
    echo "Value of scaff_R1_fastqgz: '${scaff_R1_fastqgz[@]}'"
    echo "Value of scaff_R2_fastqgz: '${scaff_R2_fastqgz[@]}'"

    # download reads
    for i in ${!scaff_R1_fastqgz[@]}
    do
        # download read 1
        if [[ "${scaff_R1_fastqgz_name[$i]}" =~ \.gz$ ]]; then
            dx download "${scaff_R1_fastqgz[$i]}" -o read1_$i.fastq.gz
        else
            dx download "${scaff_R1_fastqgz[$i]}" -o - | gzip > read1_$i.fastq.gz
        fi

       # process
       /usr/bin/scaff-bin/scaff_BC-reads-1 read1_${i}.fastq.gz read_${i}-BC_1.fastq.gz read_${i}-BC.name
       # remove extra files
       rm read1_${i}.fastq.gz
       
       # download read 2
       if [[ "${scaff_R2_fastqgz_name[$i]}" =~ \.gz$ ]]; then
            dx download "${scaff_R2_fastqgz[$i]}" -o read2_$i.fastq.gz
       else
            dx download "${scaff_R2_fastqgz[$i]}" -o - | gzip > read2_$i.fastq.gz
       fi
       
       # process
       /usr/bin/scaff-bin/scaff_BC-reads-2 read_${i}-BC.name read2_${i}.fastq.gz read_${i}-BC_2.fastq.gz
       # remove extra files
       rm read2_${i}.fastq.gz
       rm read_${i}-BC.name
    done

    # concatenate parts together
    r1_output_name="read-BC_1.fastq"
    r2_output_name="read-BC_2.fastq"
    cat read_*BC_1.fastq  > $r1_output_name
    rm read_*BC_1.fastq
    cat read_*BC_2.fastq > $r2_output_name
    rm read_*BC_2.fastq

    # sanity check: check that files aren't empty
    if [[ ! -s $r1_output_name || ! -s $r2_output_name ]]; then
        dx-jobutil-report-error "Output files are empty" AppInternalError
    fi
    
    ls -la $r1_output_name $r2_output_name
    # upload outputs
    read_bc1=$(gzip --fast $r1_output_name --stdout | dx upload - --brief --wait --destination $r1_output_name.gz)
    read_bc2=$(gzip --fast $r2_output_name --stdout | dx upload - --brief --wait --destination $r2_output_name.gz)

    dx-jobutil-add-output read_bc1 "$read_bc1" --class=file 
    dx-jobutil-add-output read_bc2 "$read_bc2" --class=file 
}

main() {
    echo "Value of assemble_genome_fastagz: '$assemble_genome_fastagz'"
    echo "Value of scaff_R1_fastqgz: '${scaff_R1_fastqgz[@]}'"
    echo "Value of scaff_R2_fastqgz: '${scaff_R2_fastqgz[@]}'"
    echo "Value of mapper_choice: '$mapper_choice'"
    echo "Value of mapper_file: '$mapping_file'"
    echo "Value of alignment_option: '$alignment_option'"
    echo "Value of break10x_option: '$break10x_option'"

    # sanity check inputs
    if [ "${#scaff_R1_fastqgz[@]}" != "${#scaff_R2_fastqgz[@]}" ]; then
        exit "number of forward and reverse reads are not equal"
    fi

    # download reads in parallel
    dx-download-all-inputs --except mapper_file --except assemble_genome_fastagz --parallel

    # save inputs to input.dat
    for i in ${!scaff_R1_fastqgz[@]}; do
        echo "q1=${scaff_R1_fastqgz_path[$i]}" >> input.dat
        echo "q2=${scaff_R2_fastqgz_path[$i]}" >> input.dat
    done

    # download & unpack genome

    if [[ "$assemble_genome_fastagz_name" =~ \.gz$ ]]; then
      assemble_genome_fastagz_name="${assemble_genome_fastagz_name%.gz}"
      dx download "$assemble_genome_fastagz" -o - | gunzip > assemble_genome.fasta
    else
       dx download "$assemble_genome_fastagz" -o assemble_genome.fasta
    fi

    if [[ "$mapper_choice" == 'BWA' ]]; then
        mapper_choice='bwa'
    elif [[ "$mapper_choice" == 'SMALT' ]]; then
        mapper_choice='smalt'
    fi

    if [[ -n "$mapping_file" ]]; then
        mkdir temp_mapping_file
        if [ ${mapping_file_name: -4} == ".bam" ]; then
            dx download "$mapping_file" -o - | samtools view - > temp_mapping_file/mapping.sam
        elif [ ${mapping_file_name: -4} == ".sam" ]; then
            dx download "$mapping_file" -o temp_mapping_file/mapping.sam
        else
            exit "The extension of mapping file is neither sam nor bam"
        fi
    fi

    echo "scaffolding"
    if [[ -n "$mapping_file" ]]; then
        /usr/bin/scaff10x -nodes `nproc` $alignment_option -sam temp_mapping_file/mapping.sam -align "$mapper_choice" -data input.dat assemble_genome.fasta scaffolds.fasta
    else
        /usr/bin/scaff10x -nodes `nproc` $alignment_option -align "$mapper_choice" -file 0 -data input.dat assemble_genome.fasta scaffolds.fasta
    fi

    if [[ "$disable_break10x" == 'false' ]]; then
        echo "break point"
        /usr/bin/break10x -nodes `nproc` $break10x_option scaffolds.fasta -data input.dat scaffolds-break.fasta scaffolds-break.name
        gzip scaffolds-break.fasta
        breakpoint=$(dx upload scaffolds-break.fasta.gz --brief)
        breakpoint_name=$(dx upload scaffolds-break.name --brief)
        dx-jobutil-add-output breakpoint "$breakpoint" --class=file
        dx-jobutil-add-output breakpoint_name "$breakpoint_name" --class=file
    fi

    ls -ltr
    
    read_bc1=$(dx upload "$read_bc1_name" --wait --brief)
    read_bc2=$(dx upload "$read_bc2_name" --wait --brief)

    dx-jobutil-add-output read_bc1 "$read_bc1" --class=file 
    dx-jobutil-add-output read_bc2 "$read_bc2" --class=file
   
    # now upload the scaffolds
    if [[ $output_prefix != "" ]]; then
        scaffold_name="${output_prefix}".scaffolds.fasta.gz
    else
        scaffold_name=scaffolds.fasta.gz
    fi
    scaffold=$(gzip --fast scaffolds.fasta --stdout | dx upload - --wait --brief --destination="$scaffold_name")
    dx-jobutil-add-output scaffold "$scaffold" --class=file 

    for i in "${!other_outputs[@]}"; do
        dx-jobutil-add-output other_outputs "${other_outputs[$i]}" --class=array:file
    done
}
