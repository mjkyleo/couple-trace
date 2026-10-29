import jwt from 'jsonwebtoken';

jest.mock('../src/factory', () => ({
  createStorageProvider: jest.fn(),
}));

jest.mock('../src/auth', () => {
  const actual = jest.requireActual('../src/auth');
  return { ...actual, authorizeCouple: jest.fn() };
});

import { getUploadSign, getDownloadSign, deleteObject } from '../src/index';
import { createStorageProvider } from '../src/factory';
import { authorizeCouple } from '../src/auth';

const mockProvider = {
  getUploadUrl: jest.fn(),
  getDownloadUrl: jest.fn(),
  delete: jest.fn(),
};
(createStorageProvider as jest.Mock).mockReturnValue(mockProvider);
(authorizeCouple as jest.Mock).mockResolvedValue(true);

const token = jwt.sign({ sub: 'user-001' }, 'test-secret', { expiresIn: '1h' });

type ResLike = {
  _status: number;
  _data: unknown;
  status: (code: number) => { json: (d: unknown) => unknown };
  json: (d: unknown) => unknown;
};

function makeRes(): ResLike {
  const res = { _status: 0, _data: null } as ResLike;
  res.status = (code: number) => {
    res._status = code;
    return { json: (d: unknown) => { res._data = d; return res; } };
  };
  res.json = (d: unknown) => {
    res._data = d;
    return res;
  };
  return res;
}

function makeReq(overrides: {
  headers?: Record<string, string | string[] | undefined>;
  body?: unknown;
} = {}) {
  return {
    headers: { authorization: `Bearer ${token}` },
    body: { objectKey: 'c1/photo.jpg' },
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  process.env.TRACE_JWT_SECRET = 'test-secret';
  delete process.env.TRACE_ALLOW_INSECURE_DEV_AUTH;
  (authorizeCouple as jest.Mock).mockResolvedValue(true);
  mockProvider.getUploadUrl.mockResolvedValue('https://up.example.com?sign');
  mockProvider.getDownloadUrl.mockResolvedValue('https://dl.example.com?sign');
  mockProvider.delete.mockResolvedValue(undefined);
});

describe('云函数入口 handler', () => {
  it('无认证 → 401', async () => {
    const res = makeRes();
    await getUploadSign({ headers: {}, body: { objectKey: 'c1/x.jpg' } }, res);
    expect(res._status).toBe(401);
  });

  it('无签名 / 错误密钥的 JWT → 401（不再只解码 payload）', async () => {
    const unsigned = [
      Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url'),
      Buffer.from(JSON.stringify({ sub: 'victim-001' })).toString('base64url'),
      '',
    ].join('.');
    const wrongKey = jwt.sign({ sub: 'victim-001' }, 'other-secret');

    for (const forged of [unsigned, wrongKey]) {
      const res = makeRes();
      await getUploadSign(
        { headers: { authorization: `Bearer ${forged}` }, body: { objectKey: 'c1/x.jpg' } },
        res,
      );
      expect(res._status).toBe(401);
    }
    expect(mockProvider.getUploadUrl).not.toHaveBeenCalled();
  });

  it('未开启开发开关时 X-Trace-User-Id 头不被信任 → 401', async () => {
    const res = makeRes();
    await getUploadSign(
      { headers: { 'x-trace-user-id': 'attacker' }, body: { objectKey: 'c1/x.jpg' } },
      res,
    );
    expect(res._status).toBe(401);
  });

  it('非法 objectKey → 400', async () => {
    const res = makeRes();
    await getUploadSign(makeReq({ body: { objectKey: '../evil' } }), res);
    expect(res._status).toBe(400);
  });

  it('不属于该情侣空间 → 403', async () => {
    (authorizeCouple as jest.Mock).mockResolvedValue(false);
    const res = makeRes();
    await getUploadSign(makeReq(), res);
    expect(res._status).toBe(403);
  });

  it('getUploadSign 成功 → 200 返回签名 URL', async () => {
    const res = makeRes();
    await getUploadSign(makeReq(), res);
    expect(res._status).toBe(200);
    expect(res._data).toEqual({ url: 'https://up.example.com?sign' });
    expect(mockProvider.getUploadUrl).toHaveBeenCalledWith('c1/photo.jpg', 900);
    expect(authorizeCouple).toHaveBeenCalledWith('user-001', 'c1');
  });

  it('getDownloadSign 成功 → 200 返回下载 URL', async () => {
    const res = makeRes();
    await getDownloadSign(makeReq(), res);
    expect(res._status).toBe(200);
    expect(res._data).toEqual({ url: 'https://dl.example.com?sign' });
    expect(mockProvider.getDownloadUrl).toHaveBeenCalledWith('c1/photo.jpg', 1800);
  });

  it('deleteObject 成功 → 200 ok', async () => {
    const res = makeRes();
    await deleteObject(makeReq(), res);
    expect(res._status).toBe(200);
    expect(res._data).toEqual({ ok: true });
    expect(mockProvider.delete).toHaveBeenCalledWith('c1/photo.jpg');
  });

  it('存储层异常 → 500', async () => {
    mockProvider.getUploadUrl.mockRejectedValue(new Error('boom'));
    const res = makeRes();
    await getUploadSign(makeReq(), res);
    expect(res._status).toBe(500);
    expect((res._data as { error: string }).error).toContain('storage_error');
  });
});
