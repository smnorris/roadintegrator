import os
import tempfile
import yaml
import getpass

import click
import arcpy

import arcutil


def setup():
    """
    Read paramaters file, create required folders, .gdbs, connections
    """
    # read config/parameters
    with open("config.yml", 'r') as ymlfile:
        cfg = yaml.load(ymlfile)
    param = cfg
    # create folder structure in tmp
    param["TMP"] = os.path.join(tempfile.gettempdir(), cfg["tmpdir"])
    try:
        os.makedirs(os.path.join(param["TMP"], "tiles"))
    except OSError:
        if not os.path.isdir(os.path.join(param["TMP"], "tiles")):
            raise
    # create workspaces and point to them in the param dict
    for gdb in ["src", "prep", "out"]:
        param[gdb+"_wksp"] = arcutil.create_wksp(param["TMP"], gdb+".gdb")
    # point to tile processing folder
    param["tiledir"] = os.path.join(param["TMP"], "tiles")
    print param["TMP"]
    # get BCGW credentials
    if "BCGW_USR" not in param.keys():
        param["BCGW_USR"] = getpass.getuser()
    param["BCGW_PWD"] = getpass.getpass("Enter BCGW password:")

    # create BCGW connection if not present
    param["BCGW"] = arcutil.create_bcgw_connection(param["BCGW_USR"],
                                                   param["BCGW_PWD"])
    # get tile grid and point to it
    grid = os.path.join(param["src_wksp"], "grid")
    if not arcpy.Exists(grid):
        param["grid"] = arcutil.get_grid(os.path.join(param['BCGW'],
                                                      param["grid"]),
                                         param["src_wksp"],
                                         "grid")

    # read datalist and tile list
    param["layers"] = arcutil.read_datalist(param["datalist"])
    param["tiles"] = [t['MAP_TILE'] for t in arcutil.read_datalist(param["tilelist"])]

    # update source paths prefixed with a $ variable
    # There needs to be a lookup in config.yml for any paths other than
    # BCGW and TMP
    sources = [l["source"] for l in param["layers"] if l["source"][:1] == "$"]
    # Split the path on separators, hopefully it is properly constructed
    pathvars = set([s.split("\\")[0].strip("$") for s in sources])
    for layer in param["layers"]:
        for placeholder in pathvars:
            layer.update({"source": layer["source"].replace(placeholder,
                                                            param[placeholder])})
    return param


# define commands
@click.group()
def cli():
    pass


@cli.command()
@click.option("--layers", "-l",
              help='Comma separated list of layers to extract')
def extract(layers):
    """
    Extract and tile required source layers
    """
    setup()


@cli.command()
def integrate():
    """
    Combine all road layers into single output
    """
    setup()

if __name__ == '__main__':
    cli()
