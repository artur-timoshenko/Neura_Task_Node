export function readConfig(env = process.env) {
  for (const name of ['SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','APP_URL']) {
    if (!env[name]) throw new Error('Missing server environment variable: ' + name);
  }
  const url = new URL(env.SUPABASE_URL!);
  const app = new URL(env.APP_URL!);
  if (url.protocol !== 'https:' && url.hostname !== '127.0.0.1' && url.hostname !== 'localhost') {
    throw new Error('SUPABASE_URL must use HTTPS');
  }
  if (env.NODE_ENV === 'production' && app.protocol !== 'https:') throw new Error('APP_URL must use HTTPS');

  // Railway Buckets expose an S3-compatible endpoint. Accept both Railway's
  // native credential names and the AWS-style aliases printed by the CLI.
  const bucketValues = {
    endpoint: env.BUCKET_ENDPOINT || env.AWS_ENDPOINT_URL || env.ENDPOINT,
    accessKeyId: env.BUCKET_ACCESS_KEY_ID || env.AWS_ACCESS_KEY_ID || env.ACCESS_KEY_ID,
    secretAccessKey: env.BUCKET_SECRET_ACCESS_KEY || env.AWS_SECRET_ACCESS_KEY || env.SECRET_ACCESS_KEY,
    name: env.BUCKET_NAME || env.AWS_S3_BUCKET_NAME || env.BUCKET,
    region: env.BUCKET_REGION || env.AWS_DEFAULT_REGION || env.REGION || 'auto',
    urlStyle: (env.BUCKET_URL_STYLE || env.AWS_S3_URL_STYLE || 'virtual').toLowerCase(),
  };
  const suppliedBucketValues = [bucketValues.endpoint, bucketValues.accessKeyId, bucketValues.secretAccessKey, bucketValues.name]
    .filter(Boolean).length;
  if (suppliedBucketValues > 0 && suppliedBucketValues < 4) {
    throw new Error('Railway Bucket configuration is incomplete');
  }
  if (bucketValues.urlStyle !== 'virtual' && bucketValues.urlStyle !== 'path') {
    throw new Error('BUCKET_URL_STYLE must be virtual or path');
  }
  const bucket = suppliedBucketValues === 4 ? {
    endpoint: new URL(bucketValues.endpoint!).origin,
    accessKeyId: bucketValues.accessKeyId!,
    secretAccessKey: bucketValues.secretAccessKey!,
    name: bucketValues.name!,
    region: bucketValues.region,
    forcePathStyle: bucketValues.urlStyle === 'path',
  } : null;
  return {
    supabaseUrl: url.origin, anonKey: env.SUPABASE_ANON_KEY!, serviceKey: env.SUPABASE_SERVICE_ROLE_KEY!,
    appUrl: app.origin, signup: env.ALLOW_SIGNUP === 'true',
    port: Number(env.PORT || 3001), production: env.NODE_ENV === 'production', bucket,
  };
}
export type Config = ReturnType<typeof readConfig>;
