import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { StorageProvider, requiredEnv } from './base';

/**
 * AWS S3 / MinIO 通用实现（S3 协议兼容）。
 * 环境变量：S3_ACCESS_KEY / S3_SECRET_KEY / S3_BUCKET / S3_REGION
 * 可选：S3_ENDPOINT（MinIO 或自定义网关）、S3_FORCE_PATH_STYLE
 */
export class S3Provider implements StorageProvider {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor() {
    this.bucket = requiredEnv('S3_BUCKET');
    const endpoint = process.env.S3_ENDPOINT || undefined;
    this.client = new S3Client({
      region: requiredEnv('S3_REGION'),
      endpoint,
      forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
      credentials: {
        accessKeyId: requiredEnv('S3_ACCESS_KEY'),
        secretAccessKey: requiredEnv('S3_SECRET_KEY'),
      },
    });
  }

  async getUploadUrl(key: string, expireSeconds: number): Promise<string> {
    return getSignedUrl(
      this.client,
      new PutObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn: expireSeconds },
    );
  }

  async getDownloadUrl(key: string, expireSeconds: number): Promise<string> {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn: expireSeconds },
    );
  }

  async delete(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}
