-- Make A1 dwh_xxx schema the default for this session
SET search_path TO dwh_061;

-- -------------------------------
-- 2) DROP TABLE before attempting to create DWH schema tables
-- -------------------------------
DROP TABLE IF EXISTS ft_service_event CASCADE;
DROP TABLE IF EXISTS ft_SensorData CASCADE;

DROP TABLE IF EXISTS dim_timeday CASCADE;
DROP TABLE IF EXISTS dim_servicetype CASCADE;
DROP TABLE IF EXISTS dim_parameter CASCADE;
DROP TABLE IF EXISTS dim_technician_role_scd2 CASCADE;
DROP TABLE IF EXISTS dim_sensortype CASCADE;
DROP TABLE IF EXISTS dim_device CASCADE;
DROP TABLE IF EXISTS dim_readingmode CASCADE;
DROP TABLE IF EXISTS dim_alert CASCADE;
DROP TABLE IF EXISTS dim_emissionsource CASCADE;

-- -------------------------------
-- 3) CREATE TABLE statements for facts and dimensions
-- -------------------------------

-- Time dimension (shared)
CREATE TABLE dim_timeday (
    id INT PRIMARY KEY,
    date_value DATE NOT NULL,
    year INT NOT NULL,
    month INT NOT NULL,
    monthname VARCHAR(20) NOT NULL,
    day INT NOT NULL,
    dayname VARCHAR(20) NOT NULL,
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Device dimension (shared, 3-level hierarchy: Country → City → Device)
CREATE TABLE dim_device (
    sk_device BIGSERIAL PRIMARY KEY,
    tb_sensordevice_id INT NOT NULL,
    locationname VARCHAR(200) NOT NULL,  -- Device name or station
    locationtype VARCHAR(200) NOT NULL,  -- Urban, Industrial, etc.
    altitude INT NOT NULL,
    cityname VARCHAR(200) NOT NULL,
    countryname VARCHAR(200) NOT NULL,
    population_city INT NOT NULL,
    population_country INT NOT NULL,
    latitude DECIMAL(9,6) NOT NULL,
    longitude DECIMAL(9,6) NOT NULL,
    manufacturer VARCHAR(200) NULL,
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_device_bk UNIQUE (tb_sensordevice_id)
);

-- Service Type dimension (3-level hierarchy: ServiceGroup → Category → TypeName)
CREATE TABLE dim_servicetype (
    sk_servicetype BIGSERIAL PRIMARY KEY,
    tb_servicetype_id INT NOT NULL,
    servicegroup VARCHAR(100) NOT NULL,            -- e.g., Maintenance, Calibration
    category VARCHAR(100) NOT NULL,                -- e.g., Hardware, Software
    typename VARCHAR(200) NOT NULL,                -- e.g., Sensor Calibration
    min_required_level INT NOT NULL,               -- numeric representation of required level
    qualification_level_name VARCHAR(50) NOT NULL, -- e.g., Junior, Senior
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_servicetype_bk UNIQUE (tb_servicetype_id)
);

-- Parameter dimension (3-level hierarchy: Category → SubCategory → ParameterName)
CREATE TABLE dim_parameter (
    sk_parameter BIGSERIAL PRIMARY KEY,
    tb_param_id INT NOT NULL,
    paramname VARCHAR(200) NOT NULL,
    category VARCHAR(200) NOT NULL,
    subcategory VARCHAR(200),
    unit VARCHAR(50) NOT NULL,
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_parameter_bk UNIQUE (tb_param_id)
);

-- Technician Role (SCD Type 2)
CREATE TABLE dim_technician_role_scd2 (
    sk_technician_role BIGSERIAL PRIMARY KEY,
    badgenumber VARCHAR(255) NOT NULL,
    rolelevel INT NOT NULL,
    rolelevel_name VARCHAR(50) NOT NULL,   -- Entry, Junior, Senior, Lead
    category VARCHAR(255) NOT NULL,        -- Department or Role Type
    rolename VARCHAR(255) NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NOT NULL,            -- '9999-12-31' = current
    is_current BOOLEAN NOT NULL,
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ux_techrole_bk_timerange UNIQUE (badgenumber, effective_from, effective_to)
);

-- Optional supporting dimensions (Fact 1 only)
CREATE TABLE dim_sensortype (
    sk_sensortype BIGSERIAL PRIMARY KEY,
    tb_sensortype_id INT NOT NULL,
    typename VARCHAR(200) NOT NULL,
    manufacturer VARCHAR(200) NOT NULL,
    technology VARCHAR(200) NOT NULL,
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_sensortype_bk UNIQUE (tb_sensortype_id)
);

CREATE TABLE dim_readingmode (
    sk_readingmode BIGSERIAL PRIMARY KEY,
    tb_readingmode_id INT NOT NULL,
    modename VARCHAR(255) NOT NULL,
    latency INT NOT NULL,
    details VARCHAR(255) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    is_current BOOLEAN NOT NULL,
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_readingmode_timerange UNIQUE (tb_readingmode_id, valid_from, valid_to)
);

CREATE TABLE dim_alert (
    sk_alert BIGSERIAL PRIMARY KEY,
    tb_alert_id INT NOT NULL,
    alertname VARCHAR(255) NOT NULL,
    colour VARCHAR(255) NOT NULL,
    details VARCHAR(255) NOT NULL,
    severity_level INT NOT NULL,
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_alert_bk UNIQUE (tb_alert_id)
);

CREATE TABLE dim_emissionsource (
    sk_emissionsource BIGSERIAL PRIMARY KEY,
    tb_emissionsource_id INT NOT NULL,
    sourcetype VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    etl_load_timestamp TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_dim_emissionsource_bk UNIQUE (tb_emissionsource_id)
);

-- -------------------------------
-- FACT TABLES
-- -------------------------------

-- FACT 1: Environmental monitoring (Sensor Data)
CREATE TABLE ft_SensorData (
    id BIGSERIAL PRIMARY KEY,
    day_id INT NOT NULL,
    sk_parameter BIGINT NOT NULL,
    sk_device BIGINT NOT NULL,
    sk_sensortype BIGINT NOT NULL,
    sk_alert BIGINT NULL,
    sk_readingmode BIGINT NOT NULL,
    measure_value NUMERIC(18,2) NOT NULL,
    data_quality INT NOT NULL CHECK (data_quality BETWEEN 1 AND 5),
    alert_flag INT NOT NULL DEFAULT 0 CHECK (alert_flag IN (0,1)),
    alert_level INT NULL CHECK (alert_level BETWEEN 1001 AND 1004),
    weather_tempavgday NUMERIC(5,2) NULL,
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_SensorData_timeday FOREIGN KEY (day_id) REFERENCES dim_timeday(id),
    CONSTRAINT fk_SensorData_parameter FOREIGN KEY (sk_parameter) REFERENCES dim_parameter(sk_parameter),
    CONSTRAINT fk_SensorData_device FOREIGN KEY (sk_device) REFERENCES dim_device(sk_device),
    CONSTRAINT fk_SensorData_sensortype FOREIGN KEY (sk_sensortype) REFERENCES dim_sensortype(sk_sensortype),
    CONSTRAINT fk_SensorData_alert FOREIGN KEY (sk_alert) REFERENCES dim_alert(sk_alert),
    CONSTRAINT fk_SensorData_readingmode FOREIGN KEY (sk_readingmode) REFERENCES dim_readingmode(sk_readingmode)
);

-- FACT 2: Service and Maintenance (your focus)
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

-- Helpful indexes
CREATE INDEX ix_ft_SensorData_day ON ft_SensorData(day_id);
CREATE INDEX ix_ft_SensorData_device ON ft_SensorData(sk_device);
CREATE INDEX ix_ft_SensorData_parameter ON ft_SensorData(sk_parameter);

CREATE INDEX ix_ft_service_day ON ft_service_event(day_id);
CREATE INDEX ix_ft_service_device ON ft_service_event(sk_device);
CREATE INDEX ix_ft_service_type ON ft_service_event(sk_servicetype);
CREATE INDEX ix_ft_service_techrole ON ft_service_event(sk_technician_role);
