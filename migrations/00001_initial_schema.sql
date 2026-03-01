-- +goose Up

--
-- Salvia Schema - Cleaned for standalone Postgres
--

-- Required for beneficiary trigram search index
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Ensure public schema exists
CREATE SCHEMA IF NOT EXISTS public;
SET search_path TO public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: assignment_status_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.assignment_status_type AS ENUM (
    'active',
    'inactive',
    'discharged'
);



--
-- Name: auth_provider_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.auth_provider_type AS ENUM (
    'email',
    'google',
    'apple',
    'microsoft'
);



--
-- Name: invitation_status_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.invitation_status_type AS ENUM (
    'pending',
    'accepted',
    'expired',
    'revoked'
);



--
-- Name: note_status_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.note_status_type AS ENUM (
    'draft',
    'verified',
    'submitted'
);



--
-- Name: staff_role_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.staff_role_type AS ENUM (
    'admin',
    'staff'
);



--
-- Name: sync_status_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.sync_status_type AS ENUM (
    'pending',
    'syncing',
    'synced',
    'failed'
);



--
-- Name: generate_unique_org_slug(); Type: FUNCTION; Schema: public; Owner: postgres
--

-- +goose StatementBegin
CREATE FUNCTION public.generate_unique_org_slug() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    base_slug TEXT;
    final_slug TEXT;
    suffix TEXT;
    attempt INT := 0;
    max_attempts INT := 10;
    slug_max_length INT := 95;  -- Leave room for suffix (100 - 5 for -xxxx)
BEGIN
    -- Only generate slug if not provided or empty
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        -- Transform name to base slug with better international support
        base_slug := lower(unaccent(trim(NEW.name)));  -- José → jose (not joss)
        base_slug := regexp_replace(base_slug, '[^\w\s-]', '', 'g');  -- Remove special chars
        base_slug := regexp_replace(base_slug, '[-\s]+', '-', 'g');   -- Normalize spaces/hyphens
        base_slug := trim(both '-' from base_slug);                    -- Remove edge hyphens
        
        -- Handle empty base_slug (garbage input like "!!!" or "   ")
        IF base_slug = '' THEN
            base_slug := 'org';
        END IF;
        
        -- Enforce length limit (leave room for suffix: -xxxx = 5 chars)
        IF length(base_slug) > slug_max_length THEN
            base_slug := left(base_slug, slug_max_length);
            -- Remove trailing hyphen if truncation created one
            base_slug := rtrim(base_slug, '-');
        END IF;
        
        final_slug := base_slug;
        
        -- Loop until we find a unique slug
        WHILE attempt < max_attempts LOOP
            -- Check if slug exists (excluding current row on UPDATE)
            IF NOT EXISTS (
                SELECT 1 FROM organizations 
                WHERE slug = final_slug 
                AND (TG_OP = 'INSERT' OR id != NEW.id)
            ) THEN
                -- Slug is unique, use it
                NEW.slug := final_slug;
                
                -- Optional: Log for debugging (comment out in production)
                -- RAISE NOTICE 'Generated slug: % for organization: %', final_slug, NEW.name;
                
                RETURN NEW;
            END IF;
            
            -- Collision detected - generate random suffix
            -- Using 2 bytes = 4 hex chars (65k possibilities per base slug)
            -- For high-volume systems, consider 3 bytes: encode(gen_random_bytes(3), 'hex')
            suffix := encode(gen_random_bytes(2), 'hex');
            final_slug := base_slug || '-' || suffix;
            
            -- Ensure final slug doesn't exceed limits even with suffix
            IF length(final_slug) > 100 THEN
                base_slug := left(base_slug, 95 - length(suffix));
                final_slug := base_slug || '-' || suffix;
            END IF;
            
            attempt := attempt + 1;
        END LOOP;
        
        -- Safety: All attempts exhausted
        RAISE EXCEPTION 'Could not generate unique slug after % attempts for: %', 
            max_attempts, NEW.name;
    END IF;
    
    RETURN NEW;
END;$$;
-- +goose StatementEnd



--
-- Name: FUNCTION generate_unique_org_slug(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.generate_unique_org_slug() IS 'Automatically generates unique URL-safe slugs from organization names. Features: unaccent support for international characters, length limits, collision handling with random suffixes. Protected by organizations_slug_unique index for concurrency safety.';


--
-- Name: increment_version(); Type: FUNCTION; Schema: public; Owner: postgres
--

-- +goose StatementBegin
CREATE FUNCTION public.increment_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.version = OLD.version + 1;
  RETURN NEW;
END;
$$;
-- +goose StatementEnd



--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

-- +goose StatementBegin
CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;
-- +goose StatementEnd





--
-- Name: activity_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activity_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    user_id uuid,
    action character varying(100) NOT NULL,
    entity_type character varying(100),
    entity_id uuid,
    description text NOT NULL,
    changes jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);



--
-- Name: TABLE activity_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.activity_log IS 'System-wide activity log. Consider partitioning by month for scale.';


--
-- Name: audio_note_attachments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audio_note_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    audio_note_id uuid NOT NULL,
    file_url text NOT NULL,
    file_type character varying(50) NOT NULL,
    file_size_bytes bigint,
    mime_type character varying(100),
    caption text,
    file_order integer DEFAULT 0 NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);



--
-- Name: audio_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audio_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    beneficiary_id uuid NOT NULL,
    recorded_by uuid NOT NULL,
    audio_url text NOT NULL,
    audio_size_bytes bigint,
    duration_seconds integer,
    audio_format character varying(10) DEFAULT 'webm'::character varying,
    recorded_at timestamp with time zone NOT NULL,
    device_id character varying(255),
    sync_status public.sync_status_type DEFAULT 'pending'::public.sync_status_type NOT NULL,
    synced_at timestamp with time zone,
    sync_attempts integer DEFAULT 0 NOT NULL,
    sync_error text,
    is_processed boolean DEFAULT false NOT NULL,
    processed_at timestamp with time zone,
    raw_transcript text,
    transcript_language character varying(10) DEFAULT 'en'::character varying,
    session_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT audio_duration_positive CHECK (((duration_seconds IS NULL) OR (duration_seconds > 0)))
);



--
-- Name: beneficiaries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beneficiaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    date_of_birth date NOT NULL,
    medical_record_number character varying(50) NOT NULL,
    phone character varying(20),
    email character varying(255),
    address jsonb,
    emergency_contact jsonb,
    profile_image_url text,
    blood_type character varying(5),
    allergies text[],
    medical_history text,
    search_text text GENERATED ALWAYS AS ((((((first_name)::text || ' '::text) || (last_name)::text) || ' '::text) || (medical_record_number)::text)) STORED,
    is_active boolean DEFAULT true NOT NULL,
    deceased_at timestamp with time zone,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT beneficiary_dob_reasonable CHECK ((date_of_birth >= '1900-01-01'::date)),
    CONSTRAINT beneficiary_dob_valid CHECK ((date_of_birth <= CURRENT_DATE))
);



--
-- Name: TABLE beneficiaries; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.beneficiaries IS 'Patients/residents receiving care. Contains PHI.';


--
-- Name: COLUMN beneficiaries.search_text; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.beneficiaries.search_text IS 'Generated column for fast full-text search.';


--
-- Name: beneficiary_group_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beneficiary_group_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    beneficiary_id uuid NOT NULL,
    group_id uuid NOT NULL,
    status public.assignment_status_type DEFAULT 'active'::public.assignment_status_type NOT NULL,
    admission_date date DEFAULT CURRENT_DATE NOT NULL,
    discharge_date date,
    discharge_reason text,
    primary_caregiver_id uuid,
    assignment_notes text,
    assigned_by uuid NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT beneficiary_date_order CHECK (((discharge_date IS NULL) OR (discharge_date >= admission_date))),
    CONSTRAINT beneficiary_discharge_logic CHECK (((status <> 'discharged'::public.assignment_status_type) OR ((status = 'discharged'::public.assignment_status_type) AND (discharge_date IS NOT NULL))))
);



--
-- Name: deleted_notes_archive; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deleted_notes_archive (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    original_note_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    beneficiary_id uuid NOT NULL,
    deleted_by uuid NOT NULL,
    deleted_at timestamp with time zone DEFAULT now() NOT NULL,
    deletion_reason text NOT NULL,
    note_snapshot jsonb NOT NULL,
    audio_url text,
    all_edit_history jsonb,
    original_created_at timestamp with time zone NOT NULL,
    original_submitted_at timestamp with time zone,
    CONSTRAINT deletion_reason_min_length CHECK ((char_length(deletion_reason) >= 10))
);



--
-- Name: TABLE deleted_notes_archive; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.deleted_notes_archive IS 'Permanent archive of deleted notes for compliance.';


--
-- Name: document_flow_steps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_flow_steps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    flow_id uuid NOT NULL,
    template_id uuid NOT NULL,
    step_number integer NOT NULL,
    is_required boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT flow_step_number_positive CHECK ((step_number > 0))
);



--
-- Name: document_flows; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_flows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_sequential boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);



--
-- Name: form_templates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.form_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    template_key character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    version integer DEFAULT 1 NOT NULL,
    parent_template_id uuid,
    form_schema jsonb NOT NULL,
    ai_extraction_config jsonb,
    is_active boolean DEFAULT true NOT NULL,
    is_draft boolean DEFAULT false NOT NULL,
    published_at timestamp with time zone,
    published_by uuid,
    deprecated_at timestamp with time zone,
    category character varying(100),
    tags text[],
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);



--
-- Name: TABLE form_templates; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.form_templates IS 'Versioned form templates. Only one active version per template_key.';


--
-- Name: generated_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.generated_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    audio_note_id uuid NOT NULL,
    template_id uuid NOT NULL,
    template_version integer NOT NULL,
    beneficiary_id uuid NOT NULL,
    generated_by uuid NOT NULL,
    ai_model_version character varying(50),
    raw_transcript text,
    structured_transcript jsonb,
    filled_form_data jsonb NOT NULL,
    ai_confidence_scores jsonb,
    low_confidence_fields text[],
    status public.note_status_type DEFAULT 'draft'::public.note_status_type NOT NULL,
    verified_by uuid,
    verified_at timestamp with time zone,
    verification_notes text,
    submitted_by uuid,
    submitted_at timestamp with time zone,
    edit_count integer DEFAULT 0 NOT NULL,
    last_edited_by uuid,
    last_edited_at timestamp with time zone,
    document_flow_id uuid,
    flow_step_number integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    CONSTRAINT note_status_logic CHECK (((status = 'draft'::public.note_status_type) OR ((status = 'verified'::public.note_status_type) AND (verified_by IS NOT NULL)) OR ((status = 'submitted'::public.note_status_type) AND (verified_by IS NOT NULL) AND (submitted_by IS NOT NULL))))
);



--
-- Name: TABLE generated_notes; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.generated_notes IS 'AI-generated clinical notes with verification workflow.';


--
-- Name: COLUMN generated_notes.version; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.generated_notes.version IS 'Optimistic locking. Increment on update, check in WHERE clause.';


--
-- Name: groups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(100) NOT NULL,
    description text,
    color character varying(7) DEFAULT '#3B82F6'::character varying NOT NULL,
    icon character varying(50),
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    archived_at timestamp with time zone,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT group_color_format CHECK (((color)::text ~ '^#[0-9A-Fa-f]{6}$'::text))
);



--
-- Name: note_edit_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.note_edit_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    note_id uuid NOT NULL,
    edited_by uuid NOT NULL,
    edit_number integer NOT NULL,
    field_name character varying(255),
    old_value jsonb,
    new_value jsonb,
    change_type character varying(50),
    edit_reason text,
    is_admin_edit boolean DEFAULT false NOT NULL,
    note_snapshot_before jsonb,
    edited_at timestamp with time zone DEFAULT now() NOT NULL
);



--
-- Name: TABLE note_edit_history; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.note_edit_history IS 'Immutable audit trail of all note edits.';


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(100),
    owner_user_id uuid NOT NULL,
    settings jsonb DEFAULT '{"features": {"offline_sync": true, "ai_transcription": true, "advanced_analytics": false}, "timezone": "UTC", "date_format": "MM/DD/YYYY", "require_two_factor": false, "audio_retention_days": 0}'::jsonb NOT NULL,
    max_staff integer DEFAULT 50,
    max_beneficiaries integer DEFAULT 500,
    is_active boolean DEFAULT true NOT NULL,
    suspended_at timestamp with time zone,
    suspension_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    setup_completed boolean DEFAULT false,
    CONSTRAINT org_name_length CHECK ((char_length((name)::text) >= 2)),
    CONSTRAINT org_slug_format CHECK (((slug)::text ~ '^[a-z0-9-]+$'::text))
);



--
-- Name: TABLE organizations; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.organizations IS 'Tenant organizations. Soft delete for data retention.';


--
-- Name: staff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    role public.staff_role_type DEFAULT 'staff'::public.staff_role_type NOT NULL,
    permissions jsonb DEFAULT '{"notes": {"read": true, "create": true, "delete": false, "update_any": false, "update_own": true}, "staff": {"invite": false, "manage": false}, "dashboard": {"view": false, "export": false}, "templates": {"create": false, "manage": false}, "beneficiaries": {"read": true, "create": true, "delete": false, "update": false}}'::jsonb NOT NULL,
    employee_id character varying(50),
    title character varying(100),
    department character varying(100),
    is_active boolean DEFAULT true NOT NULL,
    deactivated_at timestamp with time zone,
    deactivation_reason text,
    invited_by uuid,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);



--
-- Name: TABLE staff; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.staff IS 'User membership in organizations with role and permissions.';


--
-- Name: COLUMN staff.permissions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.staff.permissions IS 'JSONB for flexible permissions without schema changes.';


--
-- Name: staff_group_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_group_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid NOT NULL,
    group_id uuid NOT NULL,
    assigned_by uuid NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    removed_at timestamp with time zone,
    removed_by uuid,
    is_active boolean DEFAULT true NOT NULL
);



--
-- Name: staff_invitations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    group_id uuid,
    email character varying(255) NOT NULL,
    first_name character varying(100),
    last_name character varying(100),
    token character varying(255) NOT NULL,
    role public.staff_role_type NOT NULL,
    permissions jsonb NOT NULL,
    status public.invitation_status_type DEFAULT 'pending'::public.invitation_status_type NOT NULL,
    invited_by uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    accepted_at timestamp with time zone,
    accepted_by_user_id uuid,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invite_expires_future CHECK ((expires_at > sent_at))
);



--
-- Name: template_group_visibility; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.template_group_visibility (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    group_id uuid NOT NULL,
    granted_by uuid NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);



--
-- Name: timeline_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.timeline_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    beneficiary_id uuid NOT NULL,
    entry_type character varying(50) NOT NULL,
    title character varying(500) NOT NULL,
    summary text,
    generated_note_id uuid,
    audio_note_id uuid,
    created_by uuid NOT NULL,
    created_by_name character varying(200),
    occurred_at timestamp with time zone NOT NULL,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);



--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    email_verified boolean DEFAULT false NOT NULL,
    password_hash character varying(255),
    auth_provider public.auth_provider_type DEFAULT 'email'::public.auth_provider_type NOT NULL,
    auth_provider_id character varying(255),
    first_name character varying(100),
    last_name character varying(100),
    phone character varying(20),
    profile_image_url text,
    two_factor_enabled boolean DEFAULT false NOT NULL,
    two_factor_secret character varying(100),
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    last_login_at timestamp with time zone,
    last_activity_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    deactivated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    onboarding_completed boolean DEFAULT false,
    CONSTRAINT user_email_format CHECK (((email)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'::text))
);



--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.users IS 'Global user accounts. Can belong to multiple organizations.';


--
-- Name: activity_log activity_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_log
    ADD CONSTRAINT activity_log_pkey PRIMARY KEY (id);


--
-- Name: audio_note_attachments audio_note_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_note_attachments
    ADD CONSTRAINT audio_note_attachments_pkey PRIMARY KEY (id);


--
-- Name: audio_notes audio_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_notes
    ADD CONSTRAINT audio_notes_pkey PRIMARY KEY (id);


--
-- Name: beneficiaries beneficiaries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiaries
    ADD CONSTRAINT beneficiaries_pkey PRIMARY KEY (id);


--
-- Name: beneficiary_group_assignments beneficiary_group_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT beneficiary_group_assignments_pkey PRIMARY KEY (id);


--
-- Name: beneficiaries beneficiary_unique_mrn; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiaries
    ADD CONSTRAINT beneficiary_unique_mrn UNIQUE (organization_id, medical_record_number);


--
-- Name: deleted_notes_archive deleted_notes_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deleted_notes_archive
    ADD CONSTRAINT deleted_notes_archive_pkey PRIMARY KEY (id);


--
-- Name: document_flow_steps document_flow_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flow_steps
    ADD CONSTRAINT document_flow_steps_pkey PRIMARY KEY (id);


--
-- Name: document_flows document_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flows
    ADD CONSTRAINT document_flows_pkey PRIMARY KEY (id);


--
-- Name: document_flow_steps flow_step_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flow_steps
    ADD CONSTRAINT flow_step_unique UNIQUE (flow_id, step_number);


--
-- Name: form_templates form_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT form_templates_pkey PRIMARY KEY (id);


--
-- Name: generated_notes generated_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT generated_notes_pkey PRIMARY KEY (id);


--
-- Name: groups group_unique_slug; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT group_unique_slug UNIQUE (organization_id, slug);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: note_edit_history note_edit_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_edit_history
    ADD CONSTRAINT note_edit_history_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: staff_group_assignments staff_group_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT staff_group_assignments_pkey PRIMARY KEY (id);


--
-- Name: staff_group_assignments staff_group_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT staff_group_unique UNIQUE (staff_id, group_id);


--
-- Name: staff_invitations staff_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT staff_invitations_pkey PRIMARY KEY (id);


--
-- Name: staff_invitations staff_invitations_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT staff_invitations_token_key UNIQUE (token);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: staff staff_unique_user_org; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_unique_user_org UNIQUE (user_id, organization_id);


--
-- Name: template_group_visibility template_group_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.template_group_visibility
    ADD CONSTRAINT template_group_unique UNIQUE (template_id, group_id);


--
-- Name: template_group_visibility template_group_visibility_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.template_group_visibility
    ADD CONSTRAINT template_group_visibility_pkey PRIMARY KEY (id);


--
-- Name: form_templates template_key_version_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT template_key_version_unique UNIQUE (organization_id, template_key, version);


--
-- Name: timeline_entries timeline_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT timeline_entries_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_activity_action; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_action ON public.activity_log USING btree (action, occurred_at DESC);


--
-- Name: idx_activity_entity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_entity ON public.activity_log USING btree (entity_type, entity_id, occurred_at DESC);


--
-- Name: idx_activity_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_org ON public.activity_log USING btree (organization_id, occurred_at DESC);


--
-- Name: idx_activity_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_activity_user ON public.activity_log USING btree (user_id, occurred_at DESC);


--
-- Name: idx_attachment_audio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_attachment_audio ON public.audio_note_attachments USING btree (audio_note_id, file_order);


--
-- Name: idx_audio_beneficiary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_beneficiary ON public.audio_notes USING btree (beneficiary_id, recorded_at DESC);


--
-- Name: idx_audio_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_org ON public.audio_notes USING btree (organization_id, recorded_at DESC);


--
-- Name: idx_audio_recorder; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_recorder ON public.audio_notes USING btree (recorded_by, recorded_at DESC);


--
-- Name: idx_audio_session; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_session ON public.audio_notes USING btree (session_id) WHERE (session_id IS NOT NULL);


--
-- Name: idx_audio_sync_pending; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_sync_pending ON public.audio_notes USING btree (sync_status, sync_attempts) WHERE (sync_status <> 'synced'::public.sync_status_type);


--
-- Name: idx_audio_unprocessed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audio_unprocessed ON public.audio_notes USING btree (organization_id) WHERE ((is_processed = false) AND (deleted_at IS NULL));


--
-- Name: idx_beneficiary_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_active ON public.beneficiaries USING btree (organization_id, is_active) WHERE (deleted_at IS NULL);


--
-- Name: idx_beneficiary_assign_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_assign_active ON public.beneficiary_group_assignments USING btree (group_id) WHERE (status = 'active'::public.assignment_status_type);


--
-- Name: idx_beneficiary_assign_beneficiary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_assign_beneficiary ON public.beneficiary_group_assignments USING btree (beneficiary_id);


--
-- Name: idx_beneficiary_assign_caregiver; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_assign_caregiver ON public.beneficiary_group_assignments USING btree (primary_caregiver_id) WHERE (status = 'active'::public.assignment_status_type);


--
-- Name: idx_beneficiary_assign_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_assign_group ON public.beneficiary_group_assignments USING btree (group_id, status);


--
-- Name: idx_beneficiary_group_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_group_active ON public.beneficiary_group_assignments USING btree (group_id, status, admission_date DESC) WHERE ((status = 'active'::public.assignment_status_type) AND (discharge_date IS NULL));


--
-- Name: idx_beneficiary_mrn; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_mrn ON public.beneficiaries USING btree (organization_id, medical_record_number);


--
-- Name: idx_beneficiary_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_name ON public.beneficiaries USING btree (organization_id, last_name, first_name);


--
-- Name: idx_beneficiary_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_org ON public.beneficiaries USING btree (organization_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_beneficiary_search; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_beneficiary_search ON public.beneficiaries USING gin (search_text public.gin_trgm_ops);


--
-- Name: idx_deleted_beneficiary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deleted_beneficiary ON public.deleted_notes_archive USING btree (beneficiary_id, deleted_at DESC);


--
-- Name: idx_deleted_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deleted_org ON public.deleted_notes_archive USING btree (organization_id, deleted_at DESC);


--
-- Name: idx_deleted_original; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deleted_original ON public.deleted_notes_archive USING btree (original_note_id);


--
-- Name: idx_edit_admin; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_edit_admin ON public.note_edit_history USING btree (note_id) WHERE (is_admin_edit = true);


--
-- Name: idx_edit_note; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_edit_note ON public.note_edit_history USING btree (note_id, edit_number);


--
-- Name: idx_edit_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_edit_user ON public.note_edit_history USING btree (edited_by, edited_at DESC);


--
-- Name: idx_flow_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_flow_org ON public.document_flows USING btree (organization_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_flow_step_flow; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_flow_step_flow ON public.document_flow_steps USING btree (flow_id, step_number);


--
-- Name: idx_group_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_active ON public.groups USING btree (organization_id, is_active, sort_order) WHERE (deleted_at IS NULL);


--
-- Name: idx_group_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_group_org ON public.groups USING btree (organization_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_invite_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invite_email ON public.staff_invitations USING btree (email, status);


--
-- Name: idx_invite_expires; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invite_expires ON public.staff_invitations USING btree (expires_at) WHERE (status = 'pending'::public.invitation_status_type);


--
-- Name: idx_invite_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invite_org ON public.staff_invitations USING btree (organization_id, status);


--
-- Name: idx_invite_token; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_invite_token ON public.staff_invitations USING btree (token) WHERE (status = 'pending'::public.invitation_status_type);


--
-- Name: idx_note_audio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_audio ON public.generated_notes USING btree (audio_note_id);


--
-- Name: idx_note_beneficiary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_beneficiary ON public.generated_notes USING btree (beneficiary_id, created_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: idx_note_flow; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_flow ON public.generated_notes USING btree (document_flow_id, flow_step_number) WHERE (document_flow_id IS NOT NULL);


--
-- Name: idx_note_generator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_generator ON public.generated_notes USING btree (generated_by, created_at DESC);


--
-- Name: idx_note_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_org ON public.generated_notes USING btree (organization_id, created_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: idx_note_pending_submit; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_pending_submit ON public.generated_notes USING btree (generated_by) WHERE ((status = 'verified'::public.note_status_type) AND (deleted_at IS NULL));


--
-- Name: idx_note_pending_verification; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_pending_verification ON public.generated_notes USING btree (generated_by) WHERE ((status = 'draft'::public.note_status_type) AND (deleted_at IS NULL));


--
-- Name: idx_note_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_status ON public.generated_notes USING btree (organization_id, status) WHERE (deleted_at IS NULL);


--
-- Name: idx_note_template; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_note_template ON public.generated_notes USING btree (template_id);


--
-- Name: idx_notes_beneficiary_status_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notes_beneficiary_status_date ON public.generated_notes USING btree (beneficiary_id, status, created_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: idx_notes_review_queue; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notes_review_queue ON public.generated_notes USING btree (organization_id, status, submitted_at DESC) WHERE ((status = 'submitted'::public.note_status_type) AND (deleted_at IS NULL));


--
-- Name: idx_notes_staff_pending; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_notes_staff_pending ON public.generated_notes USING btree (generated_by, status, created_at DESC) WHERE ((status = ANY (ARRAY['draft'::public.note_status_type, 'submitted'::public.note_status_type])) AND (deleted_at IS NULL));


--
-- Name: idx_org_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_org_active ON public.organizations USING btree (is_active) WHERE (deleted_at IS NULL);


--
-- Name: idx_org_owner; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_org_owner ON public.organizations USING btree (owner_user_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_org_slug; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_org_slug ON public.organizations USING btree (slug) WHERE (deleted_at IS NULL);


--
-- Name: idx_staff_assign_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_assign_group ON public.staff_group_assignments USING btree (group_id) WHERE (is_active = true);


--
-- Name: idx_staff_assign_staff; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_assign_staff ON public.staff_group_assignments USING btree (staff_id) WHERE (is_active = true);


--
-- Name: idx_staff_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_org ON public.staff USING btree (organization_id, is_active) WHERE (deleted_at IS NULL);


--
-- Name: idx_staff_permissions; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_permissions ON public.staff USING gin (permissions);


--
-- Name: idx_staff_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_role ON public.staff USING btree (organization_id, role) WHERE (deleted_at IS NULL);


--
-- Name: idx_staff_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_staff_user ON public.staff USING btree (user_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_template_vis_group; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_template_vis_group ON public.template_group_visibility USING btree (group_id);


--
-- Name: idx_template_vis_template; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_template_vis_template ON public.template_group_visibility USING btree (template_id);


--
-- Name: idx_timeline_beneficiary; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_timeline_beneficiary ON public.timeline_entries USING btree (beneficiary_id, occurred_at DESC);


--
-- Name: idx_timeline_beneficiary_chrono; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_timeline_beneficiary_chrono ON public.timeline_entries USING btree (beneficiary_id, occurred_at DESC);


--
-- Name: idx_timeline_creator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_timeline_creator ON public.timeline_entries USING btree (created_by, occurred_at DESC);


--
-- Name: idx_timeline_org; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_timeline_org ON public.timeline_entries USING btree (organization_id, occurred_at DESC);


--
-- Name: idx_timeline_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_timeline_type ON public.timeline_entries USING btree (beneficiary_id, entry_type, occurred_at DESC);


--
-- Name: idx_user_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_active ON public.users USING btree (is_active, last_activity_at DESC);


--
-- Name: idx_user_auth; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_user_auth ON public.users USING btree (auth_provider, auth_provider_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_user_email_lower; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_user_email_lower ON public.users USING btree (lower((email)::text)) WHERE (deleted_at IS NULL);


--
-- Name: organizations_slug_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX organizations_slug_unique ON public.organizations USING btree (slug);


--
-- Name: organizations organizations_slug_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER organizations_slug_trigger BEFORE INSERT OR UPDATE OF name ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.generate_unique_org_slug();


--
-- Name: audio_notes trg_audio_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_audio_updated BEFORE UPDATE ON public.audio_notes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: beneficiary_group_assignments trg_beneficiary_assign_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_beneficiary_assign_updated BEFORE UPDATE ON public.beneficiary_group_assignments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: beneficiaries trg_beneficiary_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_beneficiary_updated BEFORE UPDATE ON public.beneficiaries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: document_flows trg_flow_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_flow_updated BEFORE UPDATE ON public.document_flows FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: groups trg_group_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_group_updated BEFORE UPDATE ON public.groups FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: generated_notes trg_note_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_note_updated BEFORE UPDATE ON public.generated_notes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: generated_notes trg_note_version; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_note_version BEFORE UPDATE ON public.generated_notes FOR EACH ROW EXECUTE FUNCTION public.increment_version();


--
-- Name: organizations trg_org_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_org_updated BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: staff trg_staff_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_staff_updated BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: form_templates trg_template_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_template_updated BEFORE UPDATE ON public.form_templates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: users trg_user_updated; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_user_updated BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: audio_note_attachments fk_attachment_audio; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_note_attachments
    ADD CONSTRAINT fk_attachment_audio FOREIGN KEY (audio_note_id) REFERENCES public.audio_notes(id) ON DELETE CASCADE;


--
-- Name: audio_notes fk_audio_beneficiary; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_notes
    ADD CONSTRAINT fk_audio_beneficiary FOREIGN KEY (beneficiary_id) REFERENCES public.beneficiaries(id) ON DELETE CASCADE;


--
-- Name: audio_notes fk_audio_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_notes
    ADD CONSTRAINT fk_audio_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: audio_notes fk_audio_recorder; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audio_notes
    ADD CONSTRAINT fk_audio_recorder FOREIGN KEY (recorded_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: beneficiary_group_assignments fk_beneficiary_assign_assigned_by; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT fk_beneficiary_assign_assigned_by FOREIGN KEY (assigned_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: beneficiary_group_assignments fk_beneficiary_assign_beneficiary; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT fk_beneficiary_assign_beneficiary FOREIGN KEY (beneficiary_id) REFERENCES public.beneficiaries(id) ON DELETE CASCADE;


--
-- Name: beneficiary_group_assignments fk_beneficiary_assign_caregiver; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT fk_beneficiary_assign_caregiver FOREIGN KEY (primary_caregiver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: beneficiary_group_assignments fk_beneficiary_assign_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT fk_beneficiary_assign_group FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: beneficiary_group_assignments fk_beneficiary_assign_updated_by; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiary_group_assignments
    ADD CONSTRAINT fk_beneficiary_assign_updated_by FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: beneficiaries fk_beneficiary_creator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiaries
    ADD CONSTRAINT fk_beneficiary_creator FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: beneficiaries fk_beneficiary_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiaries
    ADD CONSTRAINT fk_beneficiary_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: beneficiaries fk_beneficiary_updater; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beneficiaries
    ADD CONSTRAINT fk_beneficiary_updater FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: deleted_notes_archive fk_deleted_beneficiary; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deleted_notes_archive
    ADD CONSTRAINT fk_deleted_beneficiary FOREIGN KEY (beneficiary_id) REFERENCES public.beneficiaries(id) ON DELETE RESTRICT;


--
-- Name: deleted_notes_archive fk_deleted_by; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deleted_notes_archive
    ADD CONSTRAINT fk_deleted_by FOREIGN KEY (deleted_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: deleted_notes_archive fk_deleted_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deleted_notes_archive
    ADD CONSTRAINT fk_deleted_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: note_edit_history fk_edit_editor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_edit_history
    ADD CONSTRAINT fk_edit_editor FOREIGN KEY (edited_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: note_edit_history fk_edit_note; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_edit_history
    ADD CONSTRAINT fk_edit_note FOREIGN KEY (note_id) REFERENCES public.generated_notes(id) ON DELETE CASCADE;


--
-- Name: document_flows fk_flow_creator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flows
    ADD CONSTRAINT fk_flow_creator FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: document_flows fk_flow_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flows
    ADD CONSTRAINT fk_flow_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: document_flow_steps fk_flow_step_flow; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flow_steps
    ADD CONSTRAINT fk_flow_step_flow FOREIGN KEY (flow_id) REFERENCES public.document_flows(id) ON DELETE CASCADE;


--
-- Name: document_flow_steps fk_flow_step_template; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_flow_steps
    ADD CONSTRAINT fk_flow_step_template FOREIGN KEY (template_id) REFERENCES public.form_templates(id) ON DELETE RESTRICT;


--
-- Name: groups fk_group_creator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_group_creator FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: groups fk_group_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_group_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: staff_invitations fk_invite_accepter; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT fk_invite_accepter FOREIGN KEY (accepted_by_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: staff_invitations fk_invite_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT fk_invite_group FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: staff_invitations fk_invite_inviter; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT fk_invite_inviter FOREIGN KEY (invited_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: staff_invitations fk_invite_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_invitations
    ADD CONSTRAINT fk_invite_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: generated_notes fk_note_audio; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_audio FOREIGN KEY (audio_note_id) REFERENCES public.audio_notes(id) ON DELETE CASCADE;


--
-- Name: generated_notes fk_note_beneficiary; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_beneficiary FOREIGN KEY (beneficiary_id) REFERENCES public.beneficiaries(id) ON DELETE CASCADE;


--
-- Name: generated_notes fk_note_editor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_editor FOREIGN KEY (last_edited_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: generated_notes fk_note_flow; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_flow FOREIGN KEY (document_flow_id) REFERENCES public.document_flows(id) ON DELETE SET NULL;


--
-- Name: generated_notes fk_note_generator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_generator FOREIGN KEY (generated_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: generated_notes fk_note_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: generated_notes fk_note_submitter; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_submitter FOREIGN KEY (submitted_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: generated_notes fk_note_template; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_template FOREIGN KEY (template_id) REFERENCES public.form_templates(id) ON DELETE RESTRICT;


--
-- Name: generated_notes fk_note_verifier; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.generated_notes
    ADD CONSTRAINT fk_note_verifier FOREIGN KEY (verified_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: organizations fk_org_owner; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT fk_org_owner FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: staff_group_assignments fk_staff_assign_assigned_by; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT fk_staff_assign_assigned_by FOREIGN KEY (assigned_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: staff_group_assignments fk_staff_assign_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT fk_staff_assign_group FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: staff_group_assignments fk_staff_assign_removed_by; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT fk_staff_assign_removed_by FOREIGN KEY (removed_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: staff_group_assignments fk_staff_assign_staff; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_group_assignments
    ADD CONSTRAINT fk_staff_assign_staff FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff fk_staff_inviter; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT fk_staff_inviter FOREIGN KEY (invited_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: staff fk_staff_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT fk_staff_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: staff fk_staff_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT fk_staff_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: form_templates fk_template_creator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT fk_template_creator FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: form_templates fk_template_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT fk_template_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: form_templates fk_template_parent; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT fk_template_parent FOREIGN KEY (parent_template_id) REFERENCES public.form_templates(id) ON DELETE SET NULL;


--
-- Name: form_templates fk_template_publisher; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_templates
    ADD CONSTRAINT fk_template_publisher FOREIGN KEY (published_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: template_group_visibility fk_template_vis_granter; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.template_group_visibility
    ADD CONSTRAINT fk_template_vis_granter FOREIGN KEY (granted_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: template_group_visibility fk_template_vis_group; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.template_group_visibility
    ADD CONSTRAINT fk_template_vis_group FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: template_group_visibility fk_template_vis_template; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.template_group_visibility
    ADD CONSTRAINT fk_template_vis_template FOREIGN KEY (template_id) REFERENCES public.form_templates(id) ON DELETE CASCADE;


--
-- Name: timeline_entries fk_timeline_audio; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT fk_timeline_audio FOREIGN KEY (audio_note_id) REFERENCES public.audio_notes(id) ON DELETE CASCADE;


--
-- Name: timeline_entries fk_timeline_beneficiary; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT fk_timeline_beneficiary FOREIGN KEY (beneficiary_id) REFERENCES public.beneficiaries(id) ON DELETE CASCADE;


--
-- Name: timeline_entries fk_timeline_creator; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT fk_timeline_creator FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: timeline_entries fk_timeline_note; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT fk_timeline_note FOREIGN KEY (generated_note_id) REFERENCES public.generated_notes(id) ON DELETE CASCADE;


--
-- Name: timeline_entries fk_timeline_org; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.timeline_entries
    ADD CONSTRAINT fk_timeline_org FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;




--
-- PostgreSQL database dump complete
--








-- +goose Down

DROP TABLE IF EXISTS deleted_notes_archive CASCADE;
DROP TABLE IF EXISTS activity_log CASCADE;
DROP TABLE IF EXISTS timeline_entries CASCADE;
DROP TABLE IF EXISTS note_edit_history CASCADE;
DROP TABLE IF EXISTS generated_notes CASCADE;
DROP TABLE IF EXISTS audio_note_attachments CASCADE;
DROP TABLE IF EXISTS audio_notes CASCADE;
DROP TABLE IF EXISTS document_flow_steps CASCADE;
DROP TABLE IF EXISTS document_flows CASCADE;
DROP TABLE IF EXISTS template_group_visibility CASCADE;
DROP TABLE IF EXISTS form_templates CASCADE;
DROP TABLE IF EXISTS beneficiary_group_assignments CASCADE;
DROP TABLE IF EXISTS staff_group_assignments CASCADE;
DROP TABLE IF EXISTS groups CASCADE;
DROP TABLE IF EXISTS staff_invitations CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS beneficiaries CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP FUNCTION IF EXISTS generate_unique_org_slug() CASCADE;
DROP FUNCTION IF EXISTS increment_version() CASCADE;
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;

DROP TYPE IF EXISTS assignment_status_type CASCADE;
DROP TYPE IF EXISTS auth_provider_type CASCADE;
DROP TYPE IF EXISTS invitation_status_type CASCADE;
DROP TYPE IF EXISTS note_status_type CASCADE;
DROP TYPE IF EXISTS staff_role_type CASCADE;
DROP TYPE IF EXISTS sync_status_type CASCADE;

DROP EXTENSION IF EXISTS pg_trgm;
