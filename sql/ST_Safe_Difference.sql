-- https://github.com/gojuno/lostgis/blob/master/sql/functions/ST_Safe_Difference.sql

-- modified only to make parallel unsafe, parallel processing is per tile, and
-- handled by Python

create or replace function ST_Safe_Difference(
    geom_a           geometry,
    geom_b           geometry default null,
    message          text default '[unspecified]',
    grid_granularity double precision default 1
)
    returns geometry as
$$
begin
    if geom_b is null or ST_IsEmpty(geom_b)
    then
        return geom_a;
    end if;
    return
    ST_Safe_Repair(
        ST_Translate(
            ST_Difference(
                ST_Translate(geom_a, -ST_XMin(geom_a), -ST_YMin(geom_a)),
                ST_Translate(geom_b, -ST_XMin(geom_a), -ST_YMin(geom_a))
            ),
            ST_XMin(geom_a),
            ST_YMin(geom_a)
        )
    );
    exception
    when others
        then
            begin
                raise notice 'ST_Safe_Difference: making everything valid';
                return
                ST_Translate(
                    ST_Safe_Repair(
                        ST_Difference(
                            ST_Translate(ST_Safe_Repair(geom_a), -ST_XMin(geom_a), -ST_YMin(geom_a)),
                            ST_Buffer(ST_Translate(geom_b, -ST_XMin(geom_a), -ST_YMin(geom_a)), 0.4 * grid_granularity)
                        )
                    ),
                    ST_XMin(geom_a),
                    ST_YMin(geom_a)
                );
                exception
                when others
                    then
                        raise warning 'ST_Safe_Difference: everything failed';
                        return ST_Safe_Repair(geom_a);
            end;
end
$$
language 'plpgsql' immutable strict parallel unsafe;