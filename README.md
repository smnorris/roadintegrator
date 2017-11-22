# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to merge the roads into a single layer.

Note that the merging process is a simple snapping of nearby roads - this is an approximation and the output should not be considered definitive. Output is for specific Cumulative Effects reporting tools and similar road density analyses; for projects requiring a clean road network please use the various source road data appropriately.

## Requirements

- Python 2.7
- PostgreSQL (tested with v10.1)
- PostGIS (tested with v2.4)
- ArcGIS Desktop (tested on v10.1+)
- ArcGIS 64 bit background geoprocessing add-on


## Setup

1. Using pip, install the required python libraries:
```
pip install --user -r requirements.txt
```
(if pip is not installed, see [installing pip](https://pip.pypa.io/en/stable/installing/))

Open a 64bit command prompt window and ensure that the 64bit Python executable is referenced in your PATH variable with this command:
```
set PATH="E:\sw_nt\Python27\ArcGISx6410.3";"E:\sw_nt\Python27\ArcGISx6410.3\Scripts";%PATH%
```

## Usage

1. Generate road lines from RESULTS roads polygons, see results_roads_lines/README.md

2. Modify configuration files as required. Changing the path to the ResultsRoads layer generated in setup above will likely be required:
    - `road_inputs.csv` - definitions (layer, query, included attributes, etc) for all inputs to analysis
    - `tiles.csv` - list of tiles to process (250k or 20k, 250 works well)
    - `config.yml` - misc config options (number of cores, grid to tile by)

3. Extract and prepare source data, writing to working folder on TEMP (as specified in `config.yml`):
`python roadintegrator.py extract`
Consider manually backing up the extract .gdb to a network drive in event of server reboot during processing.

4. Run the integration/conflation job:
`python roadintegrator.py integrate`

5. When processing is complete, copy output layer from `out.gdb` workspace on TEMP to desired location on a network drive.

**NOTE** *The integrate command spawns as many processess as specified in `config.yml`! You can potentially consume a very significant portion of a server's resources. Please be aware of other users and only run large multiprocessing jobs during non-peak hours.*

## Methodology

- create lines from RESULTS road polyons using PostGIS (see [results_road_lines](results_road_lines))
- consolidate all road sources noted in `road_inputs.csv` into a single gdb
- for each tile noted in tiles.csv (all 250k tils):
    + use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer based on input data priorities specified in `road_inputs.csv`
    + with all linework within the tolerance of `Integrage` aligned in the various sources, remove lines present in higher priority sources from lower priority datasets using the `Erase` tool
    + merge the resulting layers into a single output roads layer for the given tile
- merge all tiles into a provincial roads layer

## Performance

Integrate command only, 250k tiles:

6 cores: 21.75min;
8 cores: 16.9min;
10 cores: 14.9min;

## Todo

- multi core extract for more speed

