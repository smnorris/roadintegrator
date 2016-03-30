import os


def get_results_roads(out_folder):
    """
    Extract roads from RESULTS polygons.

    Using FME, interpret the medial axis of input polys (CenterlineReplacer
    transformer) and write to specified .gdb

    Note that RESULTS polygons to be extracted are defined as:
    ```
    STOCKING_STATUS_CODE = 'NP'
    AND STOCKING_TYPE_CODE IN ( 'RD' , 'UNN' )
    AND SILV_POLYGON_NUMBER NOT IN ('Landing', 'LND')
    ```
    """
    # dump points and spatial views
    fmwPath = os.path.join(outFolder, "fme")
    fmw = r'''E:\sw_nt\FME\fme.exe "{fmwPath}\oracle8i2geojson.fmw"
          --SourceDataset_ORACLE8I envprod1
          --DestDataset_GEOJSON "{path}\pscis_stream_cross_loc_point.json"
          --SourceDataset_GEODATABASE_SDE IDWPROD1
          --DestDataset_GEOJSON_9 "{path}\pscis_remediation_svw.json"
          --DestDataset_GEOJSON_7 "{path}\pscis_habitat_confirmation_svw.json"
          --DestDataset_GEOJSON_6 "{path}\pscis_assessment_svw.json"
          --DestDataset_GEOJSON_8 "{path}\pscis_design_proposal_svw.json"
           '''.format(fmwPath=fmwPath,
                      path=outFolder)
    os.system(fmw)