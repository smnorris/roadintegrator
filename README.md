# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer.

Note that the conflation process is an approximation and the output should not be considered definitive. Output is for specific CE reporting tools only; for other projects please use the various road data sources appropriately.

## Requirements

- access to BC Government ArcGIS terminal server
- valid BCGW credentials
- FME (tested on 2012+)
- ArcGIS (tested on 10.1+)
- Python 2.7
- pyyaml
- click

## Setup

Open a 64bit command prompt window,

Ensure that the appropriate python folder is in your PATH variable:
```
set PATH="W:\ilmb\vic\geobc\Workarea\snorris\resource_report\resource_report\src";"E:\sw_nt\Python27\ArcGISx6410.2";"E:\sw_nt\Python27\ArcGISx6410.2\Scripts";%PATH%
```
Using pip, ensure the required python libraries are available:
```
pip install click
pip install pyyaml
```
(if pip is not installed, see [installing pip](https://pip.pypa.io/en/stable/installing/))

## Usage

1. Extract RESULTS roads and convert to lines by running the FME workspace `ResultsPolyRoads2Line_FME2013.fmw`. The fmw currently only runs successfully on FME 2013, it bails when using FME 2014. Use the **Kamloops Desktop - ArcGIS 10** GTS to run this portion of the job. Note location of resulting layer for step 2 below.

2. Modify configuration files as required, you will probably have to modify the path to the Results Roads generated in step 1 above:
    - `road_inputs.csv` - definitions (layer, query, included attributes, etc) for all inputs to analysis
    - `tiles.csv` - list of 1:250,000 tiles to process
    - `config.yml` - misc config options

3. Extract and prepare source data, writing to working folder on TEMP (as specified in `config.yml`:
`python roadintegrator extract`

4. With extract complete, consider manually backing up the extract .gdb to a network drive in event of server reboot during processing

5. Run the integration/conflation job:
`python roadintegrator integrate`

6. When processing is complete, copy output layer from workspace on TEMP to desired location on a network drive.

**NOTE** *The integrate command spawns as many processess as specified in `config.yml`! If the number is greater than 4 or 5 it will consume a significant portion of a server's resources. Please be aware of other users and only run large multiprocessing jobs during non-peak hours.*

## Methodology

- extract all road sources noted in `road_inputs.csv`
- extract RESULTS polygon roads, converting features to lines by interpreting the the medial axis of input polys (CenterlineReplacer transformer)
- tile all road sources with 1:20,000 grid
- breaking processing into NTS 1:250,000 tiles, for each tile:
    + use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer based on input data priorities specified in `road_inputs.csv`
    + with all linework within the tolerance of `Integrage` aligned in the various sources, remove lines present in higher priority sources from lower priority datasets using the `Erase` tool
    + merge the resulting layers into a single output roads layer for the given tile
- merge all tiles into a provincial roads layer


