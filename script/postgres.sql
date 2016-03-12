````
--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.1
-- Dumped by pg_dump version 9.5.1

-- Started on 2016-03-11 18:51:01 CST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE cdn;
--
-- TOC entry 2120 (class 1262 OID 16386)
-- Name: cdn; Type: DATABASE; Schema: -; Owner: -
--

CREATE DATABASE cdn WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


\connect cdn

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 8 (class 2615 OID 16403)
-- Name: config; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA config;


--
-- TOC entry 6 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- TOC entry 2121 (class 0 OID 0)
-- Dependencies: 6
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 1 (class 3079 OID 12358)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 2122 (class 0 OID 0)
-- Dependencies: 1
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;


SET search_path = config, pg_catalog;

SET default_with_oids = false;

--
-- TOC entry 182 (class 1259 OID 16404)
-- Name: event; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE event (
    id integer NOT NULL,    
    servername character varying(64),
    act character varying(16),
    utime timestamp without time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 185 (class 1259 OID 16434)
-- Name: event_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

CREATE SEQUENCE event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 2123 (class 0 OID 0)
-- Dependencies: 185
-- Name: event_id_seq; Type: SEQUENCE OWNED BY; Schema: config; Owner: -
--

ALTER SEQUENCE event_id_seq OWNED BY event.id;


--
-- TOC entry 184 (class 1259 OID 16409)
-- Name: server; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE server (
    id integer NOT NULL,
    servername character varying(64),
    setting jsonb
);


--
-- TOC entry 183 (class 1259 OID 16407)
-- Name: server_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

CREATE SEQUENCE server_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 2124 (class 0 OID 0)
-- Dependencies: 183
-- Name: server_id_seq; Type: SEQUENCE OWNED BY; Schema: config; Owner: -
--

ALTER SEQUENCE server_id_seq OWNED BY server.id;


--
-- TOC entry 1992 (class 2604 OID 16436)
-- Name: id; Type: DEFAULT; Schema: config; Owner: -
--

ALTER TABLE ONLY event ALTER COLUMN id SET DEFAULT nextval('event_id_seq'::regclass);


--
-- TOC entry 1993 (class 2604 OID 16412)
-- Name: id; Type: DEFAULT; Schema: config; Owner: -
--

ALTER TABLE ONLY server ALTER COLUMN id SET DEFAULT nextval('server_id_seq'::regclass);


--
-- TOC entry 1995 (class 2606 OID 16438)
-- Name: event_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY event
    ADD CONSTRAINT event_pkey PRIMARY KEY (id);


--
-- TOC entry 1999 (class 2606 OID 16417)
-- Name: server_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY server
    ADD CONSTRAINT server_pkey PRIMARY KEY (id);


--
-- TOC entry 1996 (class 1259 OID 16419)
-- Name: event_servername; Type: INDEX; Schema: config; Owner: -
--

CREATE UNIQUE INDEX event_servername ON event USING btree (servername);


--
-- TOC entry 2000 (class 1259 OID 16418)
-- Name: server_servername; Type: INDEX; Schema: config; Owner: -
--

CREATE UNIQUE INDEX server_servername ON server USING btree (servername);


--
-- TOC entry 1997 (class 1259 OID 16445)
-- Name: utime; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX utime ON event USING btree (utime DESC);


--
-- TOC entry 2001 (class 2620 OID 16448)
-- Name: event_change; Type: TRIGGER; Schema: config; Owner: -
--

DROP TRIGGER IF EXISTS "event_change" ON "config"."server";
drop function change_event_trigger();
CREATE FUNCTION change_event_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
 begin 
  if (TG_OP = 'INSERT' OR TG_OP = 'UPDATE')  then
    insert into config.event (servername, act) select NEW.servername, 'add_config' ON CONFLICT(servername) DO UPDATE SET act='add_config',utime=now();
    return NEW;
  ELSEIF TG_OP = 'DELETE' then
    insert into config.event (servername, act) select OLD.servername, 'remove_config' ON CONFLICT(servername) DO UPDATE SET act='remove_config',utime=now();
    return NEW;
  end if;
  end;
 $$;

CREATE TRIGGER event_change AFTER INSERT OR DELETE OR UPDATE ON server FOR EACH ROW EXECUTE PROCEDURE config.change_event_trigger();


-- Completed on 2016-03-11 18:51:01 CST

--
-- PostgreSQL database dump complete
--

````