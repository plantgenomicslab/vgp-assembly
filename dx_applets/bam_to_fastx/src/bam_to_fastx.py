#!/usr/bin/env python
# bam_to_fasta 0.0.1
# Generated by dx-app-wizard.
#
# Basic execution pattern: Your app will run on a single machine from
# beginning to end.
#
# See https://wiki.dnanexus.com/Developer-Portal for documentation and
# tutorials on how to modify this file.
#
# DNAnexus Python Bindings (dxpy) documentation:
#   http://autodoc.dnanexus.com/bindings/python/current/

import os
import subprocess
import glob
import dxpy

__updated__ = "2017-10-14"
os.environ['PATH'] = os.environ['PATH'] + os.pathsep + '/opt/smrtlink/smrtcmds/bin'


def _run_cmd(cmd, returnOutput=False):
    print cmd
    if returnOutput:
        output = subprocess.check_output(
            cmd, shell=True, executable='/bin/bash').strip()
        print output
        return output
    else:
        subprocess.check_call(cmd, shell=True, executable='/bin/bash')


def _remove_special_chars(string):
    '''function that replaces any characters in a string that are not alphanumeric or _ or .'''
    string = "".join(
        char for char in string if char.isalnum() or char in ['_', '.'])

    return string


def _download_and_gunzip_file(input_file, skip_decompress=False, additional_pipe=None):
    input_file = dxpy.DXFile(input_file)
    input_filename = input_file.describe()['name']
    ofn = _remove_special_chars(input_filename)

    cmd = 'dx download ' + input_file.get_id() + ' -o - '
    if input_filename.endswith('.tar.gz') or input_filename.endswith('.tgz'):
        ofn = 'tar_output_{0}'.format(
            ofn.replace('.tar.gz', '').replace('.tgz', ''))
        cmd += '| tar -zxvf - '
    elif (os.path.splitext(input_filename)[-1] == '.gz') and not skip_decompress:
        cmd += '| gunzip '
        ofn = os.path.splitext(ofn)[0]
    if additional_pipe is not None:
        cmd += '| ' + additional_pipe
    cmd += ' > ' + ofn
    _run_cmd(cmd)

    return ofn


def _index_min(values):
    # Efficient index of min from stackoverflow.com/questions/2474015
    return min(xrange(len(values)), key=values.__getitem__)


def _schedule_lpt(jobs, num_bins):
    '''This function implements the Longest Processing Time algorithm to get
    a good division of labor for the multiprocessor scheduling problem.'''

    # We expect a list of tuples, with the first value the name of the
    # job and the second value the weight.  If we are given a dict
    # then convert keys to job names and values to weights.
    if(type(jobs) == dict):
        jobs = zip(jobs.keys(), jobs.values())
    jobs.sort(key=lambda j: j[1], reverse=True)
    partition = {'groups': [[] for i in xrange(num_bins)],
                 'size': [0 for i in xrange(num_bins)]}

    for job in jobs:
        idx = _index_min(partition['size'])
        partition['groups'][idx] += [job[0]]
        partition['size'][idx] += job[1]

    return partition


def _split_files(dxfiles, target_size):
    '''
    :param dxfiles: List of dx files to split
    :type dxfiles: list of DXLink
    :param target_size: Target size (in bytes) of each bin
    :type target_size: Int
    :returns: Groups of files
    :rtype: List of lists of DXLink

    Takes a list of dxfiles and splits it into groups attempting to have
    each group roughly the given target size worth of data.
    '''
    total_size = 0
    files_and_sizes = []
    for dxfile in dxfiles:
        size = dxpy.describe(dxfile['$dnanexus_link'])['size']
        files_and_sizes.append((dxfile, size))
        total_size += size

    # Now, get the splits.  We'll target each set of bam files to be a total
    # of target_size bytes.
    num_bins = total_size / target_size + 1
    splits = _schedule_lpt(files_and_sizes, num_bins)

    # It's conceivable that some of the splits could be empty.  We'll remove
    # those from our list.
    splits = [split for split in splits['groups'] if len(split) > 0]

    return splits


@dxpy.entry_point('convert_bams')
def convert_bams(input_bams, decompress, barcoded, min_read_length=None, added_filters=None):
    output = {'output_fastas': [],
              'output_fastqs': []}

    decompress_cmd = ' -u ' if decompress else ''
    barcode_cmd = ' --split-barcodes ' if barcoded else ''

    # Iterate over the bam files and convert them to fasta and fastq files.
    for input_bam in input_bams:
        bam_fn = _download_and_gunzip_file(input_bam)
        prefix = os.path.splitext(bam_fn)[0]
        ofn_fa = prefix + '.fasta.gz'
        ofn_fq = prefix + '.fastq.gz'
        cmd = '/opt/smrtlink/smrtcmds/bin/pbindex {0}'.format(bam_fn)
        _run_cmd(cmd)

        if min_read_length or added_filters:
            # To filter: create dataset and apply filters and conversion to dataset
            dataset_xml = prefix + '.subreadset.xml'
            cmd = 'dataset create --type SubreadSet {0} {1}'.format(dataset_xml, bam_fn)
            _run_cmd(cmd)

            cmd = 'dataset filter {0} {0} '.format(dataset_xml)
            if min_read_length:
                cmd += 'length>{0} '.format(min_read_length)
            if added_filters:
                cmd += ' '.join(added_filters.split(','))
            _run_cmd(cmd)

            bam_in = dataset_xml
        else:
            bam_in = bam_fn

        cmd = '/opt/smrtlink/smrtcmds/bin/bam2fasta {0} -o {1} {2} {3}'.format(
            bam_in, prefix, barcode_cmd, decompress_cmd)
        _run_cmd(cmd)

        cmd = '/opt/smrtlink/smrtcmds/bin/bam2fastq {0} -o {1} {2} {3}'.format(
            bam_in, prefix, barcode_cmd, decompress_cmd)
        _run_cmd(cmd)

        ofn_fa = glob.glob('{0}*.fasta*'.format(prefix))
        ofn_fq = glob.glob('{0}*.fastq*'.format(prefix))

        output_fasta = [dxpy.dxlink(
            dxpy.upload_local_file(ofn)) for ofn in ofn_fa]
        output_fastq = [dxpy.dxlink(
            dxpy.upload_local_file(ofn)) for ofn in ofn_fq]

        output['output_fastqs'].extend(output_fastq)
        output['output_fastas'].extend(output_fasta)

        cmd = 'rm {0} {1} {2}'.format(bam_fn, ' '.join(ofn_fa), ' '.join(ofn_fq))
        _run_cmd(cmd)

    return output


@dxpy.entry_point('main')
def main(input_bams, compressed_output, barcoded, chunk_size, min_read_length, added_filters):
    splits = _split_files(input_bams, chunk_size * 1000000)
    decompress = compressed_output is False
    # And launch jobs for each split.
    jobs = []
    for input_bams in splits:
        job = dxpy.new_dxjob({'input_bams': input_bams,
                              'decompress': decompress,
                              'barcoded': barcoded,
                              'min_read_length': min_read_length,
                              'added_filters': added_filters}, 'convert_bams')
        jobs.append(job)

    output = {
        'output_fastas': [job.get_output_ref('output_fastas') for job in jobs],
        'output_fastqs': [job.get_output_ref('output_fastqs') for job in jobs]}
    return output

dxpy.run()