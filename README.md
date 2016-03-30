# roadintegrator

Collect various BC road data sources, preprocess and tile, then use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer. 

Note that the conflation process is an approximation and the output should not be considered definitive. Output is for specific CE reporting tools only; for other projects please use the various road data sources appropriately.

## Requirements

- access to BC Government ArcGIS terminal server
- valid BCGW credentials
- FME (tested on 2012+)
- ArcGIS (tested on 10.1+)
- Python 2.7 
- sqlalchemy
- click

## Setup

Open a command line window by double clicking the `\util\python64_10_x.cmd` file matching the version of ArcGIS installed on the server you are using. Using pip, ensure the required python libraries are available:
```
pip install click
pip install sqlalchemy
```
(if pip is not installed, see [installing pip](https://pip.pypa.io/en/stable/installing/)

## Usage

1. Modify configuration files as required:  
    - `road_inputs.csv` - definitions (layer, query, included attributes, etc) for all inputs to analysis  
    (other than RESULTS, which is hard coded in the .fmw file)
    - `tiles.csv` - list of 1:250,000 tiles to process
    - `config.yml` - misc config options
  
2. Extract source data to working folder:  
`> python roadintegrator extract`  
Note that the extract process tiles each source layer by BCGS 1:20,000 sheet  

3. With extract complete, consider manually backing up the extract .gdb to a network drive in event of server reboot during processing  

4. Run the integration/conflation job:  
`> python roadintegrator integrate`  
Note that this spawns as many processess as specified in `config.yml` - if the number is greater than 4 or 5 it will consume a significant portion of the server's resources. Please be aware of other users and only run jobs with a large number of processes during non-peak hours.  

6. When processing is complete, copy output layer to desired location on a network drive.

## Methodology

- extract all road sources noted in `road_inputs.csv`
- extract RESULTS polygon roads, converting features to lines by interpreting the the medial axis of input polys (CenterlineReplacer transformer)
- tile all road sources with 1:20,000 grid
- breaking processing into NTS 1:250,000 tiles, for each tile
    + use the ArcGIS [Integrate tool](http://resources.arcgis.com/en/help/main/10.2/index.html#//00170000002s000000) to conflate the roads into a single layer based on input data priorities specified in `road_inputs.csv`
    + with all linework within the tolerance of `Integrage` aligned in the various sources, remove lines present in higher priority sources from lower priority datasets using the `Erase` tool
    + merge the resulting layers into a single output roads layer for the given tile
- merge all tiles into a provincial roads layer
- 

