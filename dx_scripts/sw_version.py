import dxpy
import subprocess
import time


app_id_hardcode_up_version={
    "app-FPkkQ4j0gjx97J1X1496B9zF":"purge_haplotig (bitbucket v1.0.3+ 1.Nov.2018)",
    "applet-FZzYjYQ0j3b9pVP06qg4Q97Y": "github ca23030ccf4254dfd2d3a5ea90d0eed41c24f88b",
    "app-FVVgJ7Q09zJpb0KZ9P3v1BpQ": "Solve3.2.1_04122018",
    "app-FVpb0j00px8fVZ9qPPGYxxP8": "Salsa 2.2",
    "app-FXF87GQ0yV32v3Q32v06xBvv": "smrtlink_6.0.0.47841",
    "app-Fb0JBK8012x8z3gG91Yxyj3q": "smrtlink_7.0.1.66975",
    "applet-FZY5j400j3bP4b62GxKB057v": "freebayes 1.3.1",
    "app-FPgQ4Y8086pf03z5J04ZkXF3": "longranger 2.2.2",
}
def latest_job(name_string):
    job_id = subprocess.check_output('dx find jobs --name {0} --all-jobs --state done -n 1 --brief'.format(name_string),shell=True)
    return job_id.strip()

def job_2_app(job_id):
    try:
        app_id = dxpy.describe(job_id)['app']
    except KeyError:
        app_id = dxpy.describe(job_id)['applet']
    return app_id.strip()

def app_2_version(app_id):
    try:
        version = dxpy.describe(app_id)['version']
    except KeyError:
        version = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(dxpy.describe(app_id)['created']))
    return version

def app_2_upversion(app_id):
    try:
        upversion = dxpy.describe(app_id)['details']['upstreamVersion']
    except KeyError:
        if app_id in app_id_hardcode_up_version:
            return app_id_hardcode_up_version[app_id]
        else:
            upversion = 'NA'
    return upversion.strip()

def start_time(job_id):
    epoch_time=dxpy.describe(job_id)['startedRunning']
    startedRunning = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(epoch_time))
    return startedRunning

falcon_job_id=latest_job("*alcon*aligner*")
falcon_unzip_job_id=latest_job("*nzip*olish*")
purge_job_id=latest_job("*purge*")
scaff10x_job_id=latest_job("Scaff10x*")
bionano_job_id=latest_job("Bionano*")
salsa_job_id=latest_job("Salsa*")
polish_job_id=latest_job("polish")
longranger_job_id=latest_job("10X*Longranger*Align*")
freebayes_job_id=latest_job("Free*ayes*")

attributes=[]

job_list = [falcon_job_id,falcon_unzip_job_id,purge_job_id,scaff10x_job_id,bionano_job_id,
              salsa_job_id,polish_job_id,longranger_job_id,freebayes_job_id]
app_list = map(job_2_app,job_list)
attributes.append(['falcon','falcon_unzip','purge','scaff10x','bionano','salsa','polish','longranger','freebayes'])
attributes.append(job_list)
attributes.append(map(start_time,job_list))
attributes.append(app_list)
attributes.append(map(app_2_version,app_list))
attributes.append(map(app_2_upversion,app_list))


for attribute in attributes:
    print('\t'.join(attribute))