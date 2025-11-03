-- Make A1 dwh_xxx schema the default for this session
SET search_path TO dwh_061;

-- -------------------------------
-- 2) DROP TABLE before attempting to create DWH schema tables
-- -------------------------------
DROP TABLE IF EXISTS dim_timeday;
DROP TABLE IF EXISTS dim_servicetype;
DROP TABLE IF EXISTS dim_parameter;
DROP TABLE IF EXISTS dim_technician_role_scd2;
--- and so on ...
DROP TABLE IF EXISTS ft_name1;
DROP TABLE IF EXISTS ft_name2;

-- -------------------------------
-- 3) CREATE TABLE statements for facts and dimensions
-- Please make sure the order in which individual statements are executed respects the FOREIGN KEY constraints
-- -------------------------------
CREATE TABLE dim_timeday (
    id INT PRIMARY KEY
    , date_value DATE NOT NULL
    , year INT NOT NULL
    , month INT NOT NULL
    , monthname VARCHAR(20) NOT NULL
    , day INT NOT NULL
    , dayname VARCHAR(20) NOT NULL
    , etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE dim_servicetype (
  sk_servicetype BIGSERIAL PRIMARY KEY       -- SK
  , tb_servicetype_id INT NOT NULL           -- ID from OLTP
  , typename VARCHAR(200) NOT NULL
  , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
  , CONSTRAINT uq_dim_servicetype_bk UNIQUE (tb_servicetype_id)
);

CREATE TABLE dim_parameter (
  sk_parameter BIGSERIAL PRIMARY KEY   -- SK
  , tb_param_id INT NOT NULL           -- ID from OLTP
  , paramname VARCHAR(200) NOT NULL    -- e.g., 'PM2', 'Mercury'
  , category VARCHAR(200) NOT NULL     -- e.g. Particulate matter, Heavy Metal
  , unit VARCHAR(50) NOT NULL          -- e.g., 'count/m3'
  , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
  , CONSTRAINT uq_dim_parameter_bk UNIQUE (tb_param_id)
);

CREATE TABLE dim_technician_role_scd2 (
  sk_technician_role BIGSERIAL PRIMARY KEY
  , badgenumber VARCHAR(255) NOT NULL   -- business key
  , rolelevel INT NOT NULL
  , category VARCHAR(255) NOT NULL
  , rolename               VARCHAR(255) NOT NULL
  , effective_from         DATE NOT NULL
  , effective_to           DATE NOT NULL  -- '9999-12-31' for current
  , is_current             BOOLEAN NOT NULL
  , etl_load_timestamp     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(0)
  , CONSTRAINT ux_techrole_bk_timerange UNIQUE (badgenumber, effective_from, effective_to)
);


-- manually added dimensions
CREATE TABLE dim_sensortype(
  sk_sensortype BIGSERIAL PRIMARY KEY
  , tb_sensortype_id INT NOT NULL
  , typename VARCHAR(200) NOT NULL
  , manufacturer VARCHAR(200) NOT NULL
  , technology VARCHAR(200) NOT NULL
  , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
  , CONSTRAINT uq_dim_sensortype_bk UNIQUE (tb_sensortype_id)
);


CREATE TABLE dim_device(
    sk_device BIGSERIAL PRIMARY KEY
    , tb_sensordevice_id INT NOT NULL
    , locationname VARCHAR(200) NOT NULL
    , locationtype VARCHAR(200) NOT NULL
    , altitude INT NOT NULL
    , cityname VARCHAR(200) NOT NULL
    , countryname VARCHAR(200) NOT NULL
    , population_city INT NOT NULL
    , population_country INT NOT NULL
    , latitude DECIMAL (9,6) NOT NULL
    , longitude DECIMAL (9,6) NOT NULL
    , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
    , CONSTRAINT uq_dim_device_bk UNIQUE (tb_sensordevice_id)
  ); 

CREATE TABLE dim_readingmode (
    sk_readingmode BIGSERIAL PRIMARY KEY
    , tb_readingmode_id INT NOT NULL
    , modename VARCHAR(255) NOT NULL
    , latency INT NOT NULL
    , details VARCHAR(255) NOT NULL
    , valid_from DATE NOT NULL
    , valid_to DATE NOT NULL
    , is_current BOOLEAN NOT NULL
    , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
    , CONSTRAINT uq_dim_readingmode_timerange UNIQUE (tb_readingmode_id, valid_from, valid_to)
);

CREATE TABLE dim_alert (
    sk_alert BIGSERIAL PRIMARY KEY
    , tb_alert_id INT NOT NULL
    , alertname VARCHAR(255) NOT NULL
    , colour VARCHAR(255) NOT NULL
    , details VARCHAR(255) NOT NULL
    , severity_level INT NOT NULL
    , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
    , CONSTRAINT uq_dim_alert_bk UNIQUE (tb_alert_id)
);

CREATE TABLE dim_emissionsource (
    sk_emissionsource BIGSERIAL PRIMARY KEY
    , tb_emissionsource_id INT NOT NULL
    , sourcetype VARCHAR(100) NOT NULL
    , description VARCHAR(255)
    , etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP
    , CONSTRAINT uq_dim_emissionsource_bk UNIQUE (tb_emissionsource_id)
);


-- FACT 1: environmental monitoring and sensor data
CREATE TABLE ft_SensorData (
    id BIGSERIAL PRIMARY KEY                 
    , day_id INT NOT NULL                        
    , sk_parameter BIGINT NOT NULL
    , sk_device BIGINT NOT NULL               
    , sk_sensortype  BIGINT NOT NULL
    , sk_alert       BIGINT NULL
    , sk_readingmode BIGINT NOT NULL
    -- (optional) add your measures here, e.g.: measure_value NUMERIC(18,2) NOT NULL,
    , measure_value NUMERIC(18,2) NOT NULL
    , data_quality INT NOT NULL CHECK (data_quality BETWEEN 1 AND 5)
    , alert_flag INT NOT NULL DEFAULT 0 CHECK (alert_flag IN (0,1))
    , alert_level INT NULL CHECK (alert_level BETWEEN 1001 AND 1004)
    , weather_tempavgday NUMERIC(5,2) NULL
    , etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    , CONSTRAINT fk_SensorData_timeday FOREIGN KEY (day_id) REFERENCES dim_timeday(id)
    , CONSTRAINT fk_SensorData_parameter FOREIGN KEY (sk_parameter) REFERENCES dim_parameter(sk_parameter)
    , CONSTRAINT fk_SensorData_device FOREIGN KEY (sk_device) REFERENCES dim_device(sk_device)
    , CONSTRAINT fk_SensorData_sensortype FOREIGN KEY (sk_sensortype) REFERENCES dim_sensortype(sk_sensortype)
    , CONSTRAINT fk_SensorData_alert FOREIGN KEY (sk_alert) REFERENCES dim_alert(sk_alert)
    , CONSTRAINT fk_SensorData_readingmode FOREIGN KEY (sk_readingmode) REFERENCES dim_readingmode(sk_readingmode)
);
-- helpful indexes for join performance (optional but recommended)
CREATE INDEX ix_ft_SensorData_day           ON ft_SensorData(day_id);
CREATE INDEX ix_ft_SensorData_parameter     ON ft_SensorData(sk_parameter);
CREATE INDEX ix_ft_SensorData_device   ON ft_SensorData(sk_device);
CREATE INDEX ix_ft_SensorData_sensortype    ON ft_SensorData(sk_sensortype);
CREATE INDEX ix_ft_SensorData_readingmode   ON ft_SensorData(sk_readingmode);

-- FACT 2: linked to TimeDay + Parameter + Technician Role (SCD2)
CREATE TABLE ft_service_event (
    id BIGSERIAL PRIMARY KEY,
    day_id INT NOT NULL,
    sk_device BIGINT NOT NULL,
    sk_servicetype BIGINT NOT NULL,
    sk_technician_role BIGINT NOT NULL,
    service_cost NUMERIC(10,2) NOT NULL,
    service_duration_minutes INT NOT NULL,
    service_quality_score INT NOT NULL CHECK (service_quality_score BETWEEN 1 AND 5),
    underqualified_flag BOOLEAN NOT NULL DEFAULT FALSE,
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_service_day FOREIGN KEY (day_id) REFERENCES dim_timeday(id),
    CONSTRAINT fk_service_device FOREIGN KEY (sk_device) REFERENCES dim_device(sk_device),
    CONSTRAINT fk_service_type FOREIGN KEY (sk_servicetype) REFERENCES dim_servicetype(sk_servicetype),
    CONSTRAINT fk_service_techrole FOREIGN KEY (sk_technician_role) REFERENCES dim_technician_role_scd2(sk_technician_role)
);


-- helpful indexes for join performance (optional but recommended)
CREATE INDEX ix_ft_service_day ON ft_service_event(day_id);
CREATE INDEX ix_ft_service_device ON ft_service_event(sk_device);
CREATE INDEX ix_ft_service_type ON ft_service_event(sk_servicetype);
CREATE INDEX ix_ft_service_techrole ON ft_service_event(sk_technician_role);



