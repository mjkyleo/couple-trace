import jwt from 'jsonwebtoken';

jest.mock('cos-nodejs-sdk-v5', () => {
  const getObjectUrl = jest.fn(
    (
      params: unknown,
      callback?: (err: null, data: { Url: string }) => void,
    ) => {
      if (typeof callback === 'function') {
        callback(null, { Url: 'https://cos.example.com/sign' });
      }
      return 'https://cos.example.com/plain';
    },
  );
  const deleteObject = jest.fn().mockResolvedValue({});
  return {
    __esModule: true,
    default: jest.fn().mockImplementation(() => ({
      getObjectUrl: getObjectUrl,
      deleteObject: deleteObject,
    })),
    __getObjectUrl: getObjectUrl,
    __deleteObject: deleteObject,
  };
});

jest.mock('ali-oss', () => {
  const signatureUrl = jest.fn();
  const deleteFile = jest.fn();
  return {
    __esModule: true,
    default: jest.fn().mockImplementation(() => ({
      signatureUrl: signatureUrl,
      delete: deleteFile,
    })),
    __signatureUrl: signatureUrl,
    __deleteFile: deleteFile,
  };
});

jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn().mockResolvedValue('https://signed-url.example.com/object'),
}));

import { validateObjectKey, extractCoupleId, resolveUid, authorizeCouple } from '../src/auth';
import { createStorageProvider } from '../src/factory';
import { CosProvider } from '../src/cos';
import { OssProvider } from '../src/oss';
import { S3Provider } from '../src/s3';

const cosMock = jest.requireMock('cos-nodejs-sdk-v5') as {
  __getObjectUrl: jest.Mock;
  __deleteObject: jest.Mock;
};
const ossMock = jest.requireMock('ali-oss') as {
  __signatureUrl: jest.Mock;
  __deleteFile: jest.Mock;
};

const COS_ENV = {
  COS_SECRET_ID: 'cos-id',
  COS_SECRET_KEY: 'cos-key',
  COS_BUCKET: 'trace-bucket',
  COS_REGION: 'ap-beijing',
};
const OSS_ENV = {
  OSS_ACCESS_KEY: 'oss-ak',
  OSS_SECRET: 'oss-sk',
  OSS_BUCKET: 'trace-bucket',
  OSS_REGION: 'oss-cn-hangzhou',
};
const S3_ENV = {
  S3_ACCESS_KEY: 's3-ak',
  S3_SECRET_KEY: 's3-sk',
  S3_BUCKET: 'trace-bucket',
  S3_REGION: 'ap-southeast-1',
};

function setEnv(map: Record<string, string>) {
  for (const [k, v] of Object.entries(map)) process.env[k] = v;
}
function clearEnv(keys: string[]) {
  for (const k of keys) delete process.env[k];
}

beforeEach(() => {
  cosMock.__getObjectUrl.mockClear();
  cosMock.__deleteObject.mockClear();
  ossMock.__signatureUrl.mockClear();
  ossMock.__deleteFile.mockClear();
  delete process.env.STORAGE_PROVIDER;
  clearEnv([...Object.keys(COS_ENV), ...Object.keys(OSS_ENV), ...Object.keys(S3_ENV)]);
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
});

// ---------------- validateObjectKey ----------------

describe('validateObjectKey', () => {
  it('接受合法 key', () => {
    expect(validateObjectKey('f47ac10b-58cc-4372-a567-0e02b2c3d479/a/photo.jpg')).toBe(true);
    expect(validateObjectKey('couple-01/20261029/video_1.mp4')).toBe(true);
    expect(validateObjectKey('abc/def-ghi.jkl')).toBe(true);
  });

  it('拒绝路径穿越', () => {
    expect(validateObjectKey('../secret')).toBe(false);
    expect(validateObjectKey('couple/../etc/passwd')).toBe(false);
  });

  it('拒绝空值、斜杠开头/结尾、超长、非字符串', () => {
    expect(validateObjectKey('')).toBe(false);
    expect(validateObjectKey('/a/b')).toBe(false);
    expect(validateObjectKey('a/b/')).toBe(false);
    expect(validateObjectKey('x'.repeat(700))).toBe(false);
    expect(validateObjectKey(123 as unknown)).toBe(false);
    expect(validateObjectKey(undefined as unknown)).toBe(false);
    expect(validateObjectKey('无汉字路径/中文名.jpg')).toBe(false);
  });
});

describe('extractCoupleId', () => {
  it('取第一段作为情侣空间 id', () => {
    expect(extractCoupleId('f47ac10b-58cc-4372-a567-0e02b2c3d479/x.jpg')).toBe(
      'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    );
  });
});

// ---------------- resolveUid ----------------

describe('resolveUid', () => {
  const token = jwt.sign({ sub: 'user-001' }, 'test-secret', { expiresIn: '1h' });
  const wrongKeyToken = jwt.sign({ sub: 'user-001' }, 'other-secret', { expiresIn: '1h' });
  const unsignedToken = [
    Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url'),
    Buffer.from(JSON.stringify({ sub: 'user-001' })).toString('base64url'),
    '',
  ].join('.');

  afterEach(() => {
    delete process.env.TRACE_JWT_SECRET;
    delete process.env.TRACE_ALLOW_INSECURE_DEV_AUTH;
  });

  it('配置密钥：验签通过的 Bearer JWT 解析出 sub', () => {
    process.env.TRACE_JWT_SECRET = 'test-secret';
    expect(resolveUid({ headers: { authorization: `Bearer ${token}` } })).toBe('user-001');
  });

  it('配置密钥：密钥不符或无签名的 token 一律拒绝', () => {
    process.env.TRACE_JWT_SECRET = 'test-secret';
    expect(resolveUid({ headers: { authorization: `Bearer ${wrongKeyToken}` } })).toBeNull();
    expect(resolveUid({ headers: { authorization: `Bearer ${unsignedToken}` } })).toBeNull();
  });

  it('未配置密钥：不退回只解码，直接拒绝', () => {
    delete process.env.TRACE_JWT_SECRET;
    expect(resolveUid({ headers: { authorization: `Bearer ${token}` } })).toBeNull();
  });

  it('显式开启开发开关后，才接受无签名 token 与 X-Trace-User-Id 头', () => {
    process.env.TRACE_ALLOW_INSECURE_DEV_AUTH = '1';
    expect(resolveUid({ headers: { authorization: `Bearer ${token}` } })).toBe('user-001');
    expect(resolveUid({ headers: { 'x-trace-user-id': 'local-user' } })).toBe('local-user');
  });

  it('未开启开发开关时 X-Trace-User-Id 头不被信任', () => {
    delete process.env.TRACE_ALLOW_INSECURE_DEV_AUTH;
    expect(resolveUid({ headers: { 'x-trace-user-id': 'local-user' } })).toBeNull();
  });

  it('无认证信息返回 null', () => {
    expect(resolveUid({ headers: {} })).toBeNull();
    expect(resolveUid({})).toBeNull();
  });
});

// ---------------- factory ----------------

describe('createStorageProvider', () => {
  it('cos → CosProvider', () => {
    process.env.STORAGE_PROVIDER = 'cos';
    setEnv(COS_ENV);
    expect(createStorageProvider()).toBeInstanceOf(CosProvider);
  });

  it('oss → OssProvider', () => {
    process.env.STORAGE_PROVIDER = 'oss';
    setEnv(OSS_ENV);
    expect(createStorageProvider()).toBeInstanceOf(OssProvider);
  });

  it('s3 与 minio → S3Provider', () => {
    process.env.STORAGE_PROVIDER = 's3';
    setEnv(S3_ENV);
    expect(createStorageProvider()).toBeInstanceOf(S3Provider);
    process.env.STORAGE_PROVIDER = 'minio';
    expect(createStorageProvider()).toBeInstanceOf(S3Provider);
  });

  it('未知厂商抛错', () => {
    process.env.STORAGE_PROVIDER = 'unknown';
    expect(() => createStorageProvider()).toThrow(/Unsupported STORAGE_PROVIDER/);
  });
});

// ---------------- COS 实现 ----------------

describe('CosProvider', () => {
  beforeEach(() => setEnv(COS_ENV));

  it('getUploadUrl 使用 PUT 方法并透传 Bucket/Key/过期时间', async () => {
    const p = new CosProvider();
    const url = await p.getUploadUrl('c1/photo.jpg', 900);
    expect(url).toBe('https://cos.example.com/sign');
    expect(cosMock.__getObjectUrl).toHaveBeenCalledWith(
      expect.objectContaining({
        Bucket: 'trace-bucket',
        Region: 'ap-beijing',
        Key: 'c1/photo.jpg',
        Method: 'PUT',
        Expires: 900,
      }),
      expect.any(Function),
    );
  });

  it('getDownloadUrl 使用 GET 方法', async () => {
    const p = new CosProvider();
    await p.getDownloadUrl('c1/video.mp4', 1800);
    expect(cosMock.__getObjectUrl).toHaveBeenCalledWith(
      expect.objectContaining({ Method: 'GET', Expires: 1800 }),
      expect.any(Function),
    );
  });

  it('delete 调用 deleteObject', async () => {
    cosMock.__deleteObject.mockResolvedValue({});
    const p = new CosProvider();
    await p.delete('c1/photo.jpg');
    expect(cosMock.__deleteObject).toHaveBeenCalledWith(
      expect.objectContaining({ Bucket: 'trace-bucket', Key: 'c1/photo.jpg' }),
    );
  });
});

// ---------------- OSS 实现 ----------------

describe('OssProvider', () => {
  beforeEach(() => setEnv(OSS_ENV));

  it('getUploadUrl 调用 signatureUrl PUT', async () => {
    ossMock.__signatureUrl.mockResolvedValue('https://oss.example.com/up?sign');
    const p = new OssProvider();
    const url = await p.getUploadUrl('c1/photo.jpg', 900);
    expect(url).toBe('https://oss.example.com/up?sign');
    expect(ossMock.__signatureUrl).toHaveBeenCalledWith('c1/photo.jpg', {
      expires: 900,
      method: 'PUT',
    });
  });

  it('getDownloadUrl 调用 signatureUrl 默认 GET', async () => {
    ossMock.__signatureUrl.mockResolvedValue('https://oss.example.com/dl?sign');
    const p = new OssProvider();
    await p.getDownloadUrl('c1/video.mp4', 1800);
    expect(ossMock.__signatureUrl).toHaveBeenCalledWith('c1/video.mp4', { expires: 1800 });
  });

  it('delete 调用 delete', async () => {
    ossMock.__deleteFile.mockResolvedValue({});
    const p = new OssProvider();
    await p.delete('c1/photo.jpg');
    expect(ossMock.__deleteFile).toHaveBeenCalledWith('c1/photo.jpg');
  });
});

// ---------------- S3 实现 ----------------

describe('S3Provider', () => {
  beforeEach(() => setEnv(S3_ENV));

  it('getUploadUrl/getDownloadUrl 返回预签名 URL', async () => {
    const p = new S3Provider();
    await expect(p.getUploadUrl('c1/photo.jpg', 900)).resolves.toBe(
      'https://signed-url.example.com/object',
    );
    await expect(p.getDownloadUrl('c1/photo.jpg', 1800)).resolves.toBe(
      'https://signed-url.example.com/object',
    );
  });

  it('缺少必填环境变量时抛错', () => {
    clearEnv(['S3_BUCKET']);
    expect(() => new S3Provider()).toThrow(/Missing required env var: S3_BUCKET/);
  });
});

// ---------------- authorizeCouple ----------------

describe('authorizeCouple', () => {
  it('未配置 Supabase 时拒绝放行（fail closed）', async () => {
    await expect(authorizeCouple('u1', 'c1')).rejects.toThrow(
      /SUPABASE_URL \/ SUPABASE_SERVICE_ROLE_KEY not configured/,
    );
  });
});
