import { DeleteObjectCommand, GetObjectCommand, PutBucketCorsCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import type { Config } from './config.js';
import { HttpError } from './policy.js';

const UPLOAD_TTL_SECONDS = 15 * 60;
const DOWNLOAD_TTL_SECONDS = 60 * 60;
const PREFIX = 'railway/';
const OBJECT_ROOT = 'task-files/';

let cached: { config: NonNullable<Config['bucket']>; client: S3Client } | null = null;
let corsReady: { client: S3Client; origin: string; promise: Promise<void> } | null = null;

function connection(config: Config) {
  if (!config.bucket) {
    throw new HttpError(503, 'Railway Bucket не настроен на backend');
  }
  if (!cached || cached.config !== config.bucket) {
    cached = {
      config: config.bucket,
      client: new S3Client({
        endpoint: config.bucket.endpoint,
        region: config.bucket.region,
        forcePathStyle: config.bucket.forcePathStyle,
        credentials: {
          accessKeyId: config.bucket.accessKeyId,
          secretAccessKey: config.bucket.secretAccessKey,
        },
      }),
    };
  }
  return { client: cached.client, bucket: config.bucket.name };
}

async function ensureBrowserCors(config: Config, client: S3Client, bucket: string) {
  if (!corsReady || corsReady.client !== client || corsReady.origin !== config.appUrl) {
    corsReady = {
      client,
      origin: config.appUrl,
      promise: client.send(new PutBucketCorsCommand({
        Bucket: bucket,
        CORSConfiguration: {
          CORSRules: [{
            AllowedOrigins: [config.appUrl],
            AllowedMethods: ['GET', 'HEAD', 'POST'],
            AllowedHeaders: ['*'],
            ExposeHeaders: ['ETag'],
            MaxAgeSeconds: 3600,
          }],
        },
      })).then(() => undefined),
    };
  }
  try {
    await corsReady.promise;
  } catch (error) {
    corsReady = null;
    console.error('Railway Bucket CORS configuration failed', error);
    throw new HttpError(502, 'Не удалось настроить CORS Railway Bucket');
  }
}

export const isRailwayTaskFile = (path: string) => path.startsWith(PREFIX);

export function railwayObjectKey(storedPath: string) {
  if (!isRailwayTaskFile(storedPath)) throw new HttpError(400, 'Некорректный путь файла');
  const relative = storedPath.slice(PREFIX.length);
  if (!relative || relative.includes('..') || relative.includes('\\') || relative.startsWith('/')) {
    throw new HttpError(400, 'Некорректный путь файла');
  }
  return OBJECT_ROOT + relative;
}

export async function createTaskUploadUrl(
  config: Config,
  relativePath: string,
  contentType: string,
  fileSize: number,
) {
  const { client, bucket } = connection(config);
  await ensureBrowserCors(config, client, bucket);
  const key = OBJECT_ROOT + relativePath;
  const grant = await createPresignedPost(client, {
    Bucket: bucket,
    Key: key,
    Expires: UPLOAD_TTL_SECONDS,
    Fields: { 'Content-Type': contentType },
    Conditions: [
      ['eq', '$key', key],
      ['eq', '$Content-Type', contentType],
      ['content-length-range', 1, fileSize],
    ],
  });
  return { path: PREFIX + relativePath, uploadUrl: grant.url, fields: grant.fields };
}

export async function createTaskDownloadUrl(config: Config, storedPath: string, downloadName?: string) {
  const { client, bucket } = connection(config);
  const command = new GetObjectCommand({
    Bucket: bucket,
    Key: railwayObjectKey(storedPath),
    ResponseContentDisposition: downloadName
      ? `attachment; filename*=UTF-8''${encodeURIComponent(downloadName)}`
      : undefined,
  });
  return getSignedUrl(client, command, { expiresIn: DOWNLOAD_TTL_SECONDS });
}

export async function deleteTaskObject(config: Config, storedPath: string) {
  const { client, bucket } = connection(config);
  await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: railwayObjectKey(storedPath) }));
}
