CREATE OR replace FUNCTION ST_ApproximateMedialAxisIgnoreErrors(arg geometry)
RETURNS geometry LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        RETURN ST_ApproximateMedialAxis(arg);
    EXCEPTION WHEN OTHERS THEN
        RETURN null;
    end;
END $$;