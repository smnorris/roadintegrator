# Road Integration   (Simon Norris)

## Set up / install dependencies

The script is called from the command line. Ensure that your python path is correct
by creating a DOS launch file (it doesn't seem possible to modify environment settings
on GTS) as noted here:
https://sites.google.com/site/bcgeopython/examples/installing-pip

    If you need to run python script from the command line routinely and you do not have 
    the ability to modify your PATH environment variable, or for some reason do not want to 
    (say multiple python installs, and want the ability to switch back and forth) you can create 
    your own dos launch file that will setup any number of environment variables before the DOS 
    prompt appears.  So to do this:
    
    1) Open up a text editor
    2) Add the following lines to the text editor:
    
    set PATH=<path to python install>; <path to python install>\Scripts;%PATH%
    cmd /p
    
    3) Now save the file (I like to keep this one on my desktop) and make sure the file has a .cmd suffix.
    
    Now test by double clicking on your file from and explorer.  It should open up a dos prompt.  
    Test to make sure the paths have actually been set by trying to call python.  

The road_integrator.py script requires these additional python libraries:
- click
- sqlalchemy

If these are not installed on the GTS machine you are using, install from command line opened
with the method outlined above:
```
pip install click
pip install sqlalchemy
```
Note that your current directory must be on a drive that is local to the server (C:, T:)
 ip will bail if the command is called from a network drive such as W: or Q: (I have no idea why)

If pip is not available, install pip (python's package manager) using the latest
method: https://pip.pypa.io/en/latest/installing.html (Kevin's method noted in the prev
link is no longer current) 
 

## Steps for producing a single roads layer:

1. Create road linework from RESULTS road polygons by running `ResultsPolyRoads2Line_FME2012.fmw`. 
Be sure to use FME2012 (on ArcGIS 10.1 server) as FME2014 chokes on the process. This process 
interprets the medial axis of input polys (CenterlineReplacer transformer). 
Results polys defined as roads are where:

```
    STOCKING_STATUS_CODE = 'NP' 
    AND STOCKING_TYPE_CODE IN ( 'RD' , 'UNN' ) 
    AND SILV_POLYGON_NUMBER NOT IN ('Landing', 'LND') 
```

2. Make any necessary adjustments to `inputs.csv`, defining source layers, queries, attributes to 
retain in output, etc. Also, if necessary make any adjustments to paths of input or output data 
within the script `road_integrator.py`. All outputs are currently directed to T: to help speed up 
the job. Input .gdb is also presumed to reside on T: (be sure to maintain a copy of source data on 
a network drive in event of server reboot during processing)

3. Extract all source data to single .gdb, tiling sources by 1:20,000 sheet.
From command line, run the script with the -e flag (for extract):

`python road_integrator.py -e`

4. Ensure that the table logging progress of the job (`road_status` on GEOPRD, there may be better 
locations for this) is reset if necessary. Any tile where `start_time` is NULL will be re-processed. 
In preparation for re-run of the entire province, apply 

```
UPDATE road_status SET start_time = NULL;
UPDATE road_status SET end_time = NULL;
UPDATE road_status SET output_file = NULL;
```
It might be easier to move the log/status table to a local file - but as the table is simultaneously 
written to by multiple processes, it is handy to get Oracle to manage updates.

5. With all data extracted and indexed in `RoadSources.gdb` and the log table updated as necessary, 
run the integration part of the script in as many terminal windows as required. Each process will pull 
new tiles until there are no tiles left.
At command line, from a local drive (T: or C:, Python can't find cx_Oracle when called from a network 
drive, no idea why) `python road_integrator.py -j 1` where 1 is a distinct number for each process (in 
first cmd window, enter `-j 1`, in second cmd window enter `-j 2`, etc etc). 

6. When processing is complete, use the ArcGIS Merge tool to integrate all outputs into a single layer.

Note 
It is likely possible to get python to handle the spawning of multiple processes rather than using this 
crude method of opening individual cmd windows. 
See http://blogs.esri.com/esri/arcgis/2012/09/26/distributed-processing-with-arcgis-part-1/
