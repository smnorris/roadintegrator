import multiprocessing
from functools import partial

import click

import pgdb


def tiled_sql(sql, tile):
    """Create a connection and execute query for specified tile
    """
    db = pgdb.connect()
    db.execute("SET postgis.backend = sfcgal")
    db.execute(sql, (tile,))


@click.command()
def run():
    db = pgdb.connect()
    # create output table
    db['temp.results_roads'].drop()
    db.execute("""CREATE TABLE temp.results_roads
                    (results_roads_id SERIAL PRIMARY KEY,
                     map_tile text,
                     geom geometry)""")

    # create filter_rings function
    db.execute(db.queries["filter_rings"])

    # load query that does the work
    sql = db.queries["road_poly_to_line"]

    # get a list of all tiles
    tiles = [t for t in db["whse_basemapping.bcgs_20k_grid"].distinct('map_tile')]

    # run tiled job in parallel, with progress bar
    func = partial(tiled_sql, sql)
    pool = multiprocessing.Pool(processes=3)
    results_iter = pool.imap_unordered(func, tiles)
    with click.progressbar(results_iter, length=len(tiles)) as bar:
        for _ in bar:
            pass
    pool.close()
    pool.join()

    # dump to file
    db = pgdb.connect()
    db.pg2ogr(sql="SELECT * FROM temp.results_roads",
              driver="FileGDB",
              outfile="results_roads.gdb",
              geom_type="linestring")


if __name__ == '__main__':
    run()
