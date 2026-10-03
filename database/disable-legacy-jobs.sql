-- Use only after SMTP is tested and the new worker is ready. Does not remove data.
DO $$
DECLARE job record;
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    FOR job IN EXECUTE $q$SELECT jobid FROM cron.job WHERE jobname IN
      ('flush-telegram-deferred', 'process-email-queue', 'telegram-poll')$q$
    LOOP
      EXECUTE format('SELECT cron.unschedule(%s)', job.jobid);
    END LOOP;
  END IF;
END $$;
