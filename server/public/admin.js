// 管理后台页面逻辑（v1.5.53）
// 外置为独立 JS 文件以启用 CSP（script-src 'self'）；
// 按钮事件统一通过 data-action / data-tab 属性绑定，不使用内联 onclick。
(function () {
  'use strict';

  const API_BASE = window.location.origin;
  let sessionId = null;
  let setupSecret = null;

  function showStatus(id, type, message) {
    const el = document.getElementById(id);
    el.className = `status ${type}`;
    el.textContent = message;
  }

  function switchTab(tab) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-bar .tab').forEach(t => {
      if (t.dataset.tab === tab) t.classList.add('active');
    });
    document.getElementById('versionTab').classList.add('hidden');
    document.getElementById('securityTab').classList.add('hidden');
    document.getElementById('statusTab').classList.add('hidden');
    document.getElementById(`${tab}Tab`).classList.remove('hidden');
  }

  async function fetchWithSession(url, options = {}) {
    const headers = { ...options.headers };
    if (sessionId) {
      headers['x-session-id'] = sessionId;
    }
    const response = await fetch(url, { ...options, headers });
    const contentType = response.headers.get('content-type') || '';
    // 非 JSON 响应（通常是 404/502/nginx 错误页）
    if (!contentType.includes('application/json')) {
      const text = await response.text().catch(() => '');
      console.error('fetchWithSession: 非JSON响应', response.status, text.substring(0, 200));
      throw new Error(`服务器异常 (${response.status}): ${text.substring(0, 100)}`);
    }
    const result = await response.json();
    console.log('fetchWithSession:', url, result.code);
    // 仅在会话明确失效时才 logout（未授权/会话过期），
    // 不因 require2FA 等其他 401 场景触发 logout（避免 OTP 验证成功后 loadVersion 误触发跳回登录页）
    if (response.status === 401 && result.code === -1 &&
        (result.message === '未授权' || result.message?.includes('会话'))) {
      logout();
    }
    return result;
  }

  async function handleLogin() {
    const token = document.getElementById('tokenInput').value.trim();
    if (!token) {
      showStatus('loginStatus', 'error', '请输入管理员 Token');
      return;
    }

    const btn = document.querySelector('#step1 .btn-primary');
    if (btn) { btn.disabled = true; btn.textContent = '登录中...'; }
    showStatus('loginStatus', 'info', '正在验证...');

    try {
      const response = await fetch(`${API_BASE}/api/admin/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token })
      });
      const contentType = response.headers.get('content-type') || '';
      if (!contentType.includes('application/json')) {
        const text = await response.text().catch(() => '');
        throw new Error(`服务器异常 (${response.status})`);
      }
      const result = await response.json();

      if (result.code === 0) {
        sessionId = result.sessionId;
        if (result.twoFAEnabled) {
          document.getElementById('step1').classList.add('hidden');
          document.getElementById('step2').classList.remove('hidden');
          document.getElementById('stepDot1').classList.add('done');
          document.getElementById('stepDot2').classList.add('active');
          showStatus('otpStatus', 'info', '请输入二步验证验证码');
          document.getElementById('otpInput').focus();
        } else {
          showStatus('loginStatus', 'success', '登录成功，正在跳转...');
          setTimeout(() => showMain(), 500);
        }
      } else if (result.code === -3 && result.blocked) {
        showStatus('loginStatus', 'error', result.message);
        document.getElementById('tokenInput').disabled = true;
      } else {
        showStatus('loginStatus', 'error', result.message || '登录失败');
      }
    } catch (e) {
      showStatus('loginStatus', 'error', '网络错误: ' + e.message);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '登录'; }
    }
  }

  async function verifyOTP() {
    const token = document.getElementById('tokenInput').value.trim();
    const otp = document.getElementById('otpInput').value.trim();

    if (!otp || otp.length !== 6) {
      showStatus('otpStatus', 'error', '请输入6位验证码');
      return;
    }

    const btn = document.querySelector('#step2 .btn-primary');
    if (btn) { btn.disabled = true; btn.textContent = '验证中...'; }
    showStatus('otpStatus', 'info', '正在验证...');

    try {
      const response = await fetch(`${API_BASE}/api/admin/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, otp })
      });
      const contentType = response.headers.get('content-type') || '';
      if (!contentType.includes('application/json')) {
        const text = await response.text().catch(() => '');
        throw new Error(`服务器异常 (${response.status})`);
      }
      const result = await response.json();

      if (result.code === 0) {
        sessionId = result.sessionId;
        showStatus('otpStatus', 'success', '验证成功，正在跳转...');
        setTimeout(() => showMain(), 500);
      } else if (result.code === -3 && result.blocked) {
        showStatus('otpStatus', 'error', result.message);
        document.getElementById('otpInput').disabled = true;
      } else {
        showStatus('otpStatus', 'error', result.message || '验证码错误');
      }
    } catch (e) {
      showStatus('otpStatus', 'error', '网络错误: ' + e.message);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '验证'; }
    }
  }

  function useRecoveryCode() {
    document.getElementById('step2').classList.add('hidden');
    document.getElementById('recoveryCodeSection').classList.remove('hidden');
  }

  function backToOTP() {
    document.getElementById('recoveryCodeSection').classList.add('hidden');
    document.getElementById('step2').classList.remove('hidden');
  }

  async function verifyRecoveryCode() {
    const token = document.getElementById('tokenInput').value.trim();
    const recoveryCode = document.getElementById('recoveryInput').value.trim().toUpperCase();

    if (!recoveryCode || recoveryCode.length !== 8) {
      showStatus('recoveryStatus', 'error', '请输入8位恢复码');
      return;
    }

    const btn = document.querySelector('#recoveryCodeSection .btn-primary');
    if (btn) { btn.disabled = true; btn.textContent = '验证中...'; }
    showStatus('recoveryStatus', 'info', '正在验证...');

    try {
      const response = await fetch(`${API_BASE}/api/admin/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, recoveryCode })
      });
      const contentType = response.headers.get('content-type') || '';
      if (!contentType.includes('application/json')) {
        const text = await response.text().catch(() => '');
        throw new Error(`服务器异常 (${response.status})`);
      }
      const result = await response.json();

      if (result.code === 0) {
        sessionId = result.sessionId;
        showStatus('recoveryStatus', 'success', '验证成功，正在跳转...');
        setTimeout(() => showMain(), 500);
      } else if (result.code === -3 && result.blocked) {
        showStatus('recoveryStatus', 'error', result.message);
        document.getElementById('recoveryInput').disabled = true;
      } else {
        showStatus('recoveryStatus', 'error', result.message || '恢复码错误');
      }
    } catch (e) {
      showStatus('recoveryStatus', 'error', '网络错误: ' + e.message);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = '验证恢复码'; }
    }
  }

  async function showSetup2FA() {
    const token = document.getElementById('tokenInput').value.trim();
    if (!token) {
      showStatus('loginStatus', 'error', '请先输入管理员 Token');
      return;
    }

    try {
      const result = await fetch(`${API_BASE}/api/admin/totp/setup`, {
        headers: { 'x-admin-token': token }
      }).then(r => r.json());

      if (result.code === 0) {
        setupSecret = result.data.secret;
        document.getElementById('manualSecret').value = result.data.manualCode;
        document.getElementById('qrContainer').innerHTML = `<img src="${result.data.qrCodeUrl}" alt="二维码">`;
        document.getElementById('step1').classList.add('hidden');
        document.getElementById('setup2FA').classList.remove('hidden');
      } else {
        showStatus('loginStatus', 'error', result.message || '获取设置失败');
      }
    } catch (e) {
      showStatus('loginStatus', 'error', '网络错误: ' + e.message);
    }
  }

  function cancelSetup() {
    document.getElementById('setup2FA').classList.add('hidden');
    document.getElementById('step1').classList.remove('hidden');
    setupSecret = null;
  }

  async function enable2FA() {
    const token = document.getElementById('tokenInput').value.trim();
    const otp = document.getElementById('setupOtp').value.trim();

    if (!otp || otp.length !== 6) {
      showStatus('loginStatus', 'error', '请输入6位验证码');
      return;
    }

    try {
      const result = await fetch(`${API_BASE}/api/admin/totp/enable`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-admin-token': token },
        body: JSON.stringify({ secret: setupSecret, otp })
      }).then(r => r.json());

      if (result.code === 0) {
        document.getElementById('setup2FA').classList.add('hidden');
        document.getElementById('showRecoveryCodes').classList.remove('hidden');
        const codesList = document.getElementById('recoveryCodesList');
        codesList.innerHTML = result.data.recoveryCodes.map(c => `<div class="code">${c}</div>`).join('');
      } else {
        showStatus('loginStatus', 'error', result.message || '启用失败');
      }
    } catch (e) {
      showStatus('loginStatus', 'error', '网络错误: ' + e.message);
    }
  }

  function finishSetup() {
    handleLogin();
  }

  async function copyRecoveryCodes() {
    const codes = Array.from(document.querySelectorAll('#recoveryCodesList .code'))
      .map(e => e.textContent).join('\n');
    if (!codes) return;
    try {
      await navigator.clipboard.writeText(codes);
      const btn = document.querySelector('#showRecoveryCodes .copy-btn');
      const old = btn.textContent;
      btn.textContent = '已复制 ✓';
      setTimeout(() => { btn.textContent = old; }, 1500);
    } catch (e) {
      // 剪贴板 API 不可用时降级为提示
      alert('恢复码：\n' + codes);
    }
  }

  function showMain() {
    document.getElementById('loginSection').classList.add('hidden');
    document.getElementById('mainSection').classList.remove('hidden');
    // 延迟加载，确保 session 已完全建立
    setTimeout(() => {
      loadVersion().catch(e => console.error('loadVersion:', e));
      loadSecurityStatus().catch(e => console.error('loadSecurityStatus:', e));
    }, 100);
  }

  function logout() {
    // 服务端吊销会话（best-effort：会话已失效时返回 401 无碍）
    const sid = sessionId;
    fetch(`${API_BASE}/api/admin/logout`, {
      method: 'POST',
      headers: sid ? { 'x-session-id': sid } : {}
    }).catch(() => {});
    sessionId = null;
    document.getElementById('mainSection').classList.add('hidden');
    document.getElementById('loginSection').classList.remove('hidden');
    document.getElementById('step2').classList.add('hidden');
    document.getElementById('recoveryCodeSection').classList.add('hidden');
    document.getElementById('setup2FA').classList.add('hidden');
    document.getElementById('showRecoveryCodes').classList.add('hidden');
    document.getElementById('step1').classList.remove('hidden');
  }

  async function loadVersion() {
    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/version`);
      if (result.code === 0) {
        const data = result.data;
        document.getElementById('v_latestVersion').value = data.latestVersion || '';
        document.getElementById('v_latestBuild').value = data.latestBuild || '';
        document.getElementById('v_minSupportedVersion').value = data.minSupportedVersion || '';
        document.getElementById('v_changelog').value = data.changelog || '';
        document.getElementById('v_forceUpdate').checked = data.forceUpdate || false;
        document.getElementById('v_forceUpdateVersion').value = data.forceUpdateVersion || '';
        document.getElementById('v_forceUpdateBuild').value = data.forceUpdateBuild || '';
        toggleForceFields('v', data.forceUpdate);
        // 多平台下载配置
        const dl = data.downloads || {};
        const fs = data.fileSizes || {};
        document.getElementById('v_dl_arm64').value = dl.arm64 || '';
        document.getElementById('v_dl_arm32').value = dl.arm32 || '';
        document.getElementById('v_dl_x86').value = dl.x86_64 || '';
        document.getElementById('v_dl_all').value = dl.all || '';
        document.getElementById('v_fs_arm64').value = fs.arm64 || '';
        document.getElementById('v_fs_arm32').value = fs.arm32 || '';
        document.getElementById('v_fs_x86').value = fs.x86_64 || '';
        document.getElementById('v_fs_all').value = fs.all || '';
        document.getElementById('versionJson').textContent = JSON.stringify(data, null, 2);
        document.getElementById('versionForceBadge').classList.toggle('hidden', !data.forceUpdate);
        showStatus('versionStatus', 'success', '数据加载成功');
      } else {
        showStatus('versionStatus', 'error', result.message || '加载失败');
      }
    } catch (e) {
      showStatus('versionStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function saveVersion() {
    const data = {
      latestVersion: document.getElementById('v_latestVersion').value,
      latestBuild: parseInt(document.getElementById('v_latestBuild').value) || 0,
      minSupportedVersion: document.getElementById('v_minSupportedVersion').value,
      changelog: document.getElementById('v_changelog').value,
      forceUpdate: document.getElementById('v_forceUpdate').checked,
      forceUpdateVersion: document.getElementById('v_forceUpdateVersion').value,
      forceUpdateBuild: parseInt(document.getElementById('v_forceUpdateBuild').value) || 0,
      downloads: {
        arm64: document.getElementById('v_dl_arm64').value,
        arm32: document.getElementById('v_dl_arm32').value,
        x86_64: document.getElementById('v_dl_x86').value,
        all: document.getElementById('v_dl_all').value
      },
      fileSizes: {
        arm64: parseInt(document.getElementById('v_fs_arm64').value) || 0,
        arm32: parseInt(document.getElementById('v_fs_arm32').value) || 0,
        x86_64: parseInt(document.getElementById('v_fs_x86').value) || 0,
        all: parseInt(document.getElementById('v_fs_all').value) || 0
      }
    };
    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/version`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      if (result.code === 0) {
        showStatus('versionStatus', 'success', '保存成功');
        document.getElementById('versionJson').textContent = JSON.stringify(data, null, 2);
        document.getElementById('versionForceBadge').classList.toggle('hidden', !data.forceUpdate);
      } else {
        showStatus('versionStatus', 'error', result.message || '保存失败');
      }
    } catch (e) {
      showStatus('versionStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function loadSecurityStatus() {
    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/totp/status`);
      if (result.code === 0) {
        const data = result.data;
        document.getElementById('twoFASwitch').checked = data.enabled;
        document.getElementById('twoFAState').value = data.enabled ? '✅ 已启用' : '❌ 未启用';
        document.getElementById('twoFAStatus').className = `security-status ${data.enabled ? 'enabled' : 'disabled'}`;
        showStatus('securityStatus', 'success', '状态加载成功');
      } else {
        showStatus('securityStatus', 'error', result.message || '加载失败');
      }
    } catch (e) {
      showStatus('securityStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function toggleTwoFA() {
    const enabled = document.getElementById('twoFASwitch').checked;
    if (enabled) {
      try {
        const result = await fetchWithSession(`${API_BASE}/api/admin/totp/setup`);
        if (result.code === 0) {
          if (result.data.enabled === true) {
            // 二步验证已启用：不允许直接覆盖，回滚开关并提示
            document.getElementById('twoFASwitch').checked = false;
            showStatus('securityStatus', 'error', '二步验证已启用，如需重新绑定请点击"重新绑定二步验证"');
            return;
          }
          setupSecret = result.data.secret;
          document.getElementById('setupSecret').value = result.data.manualCode;
          document.getElementById('setupQrContainer').innerHTML = `<img src="${result.data.qrCodeUrl}" alt="二维码">`;
          document.getElementById('twoFAActions').classList.add('hidden');
          document.getElementById('twoFASetup').classList.remove('hidden');
          document.getElementById('twoFASetupTitle').textContent = '启用二步验证';
        } else {
          showStatus('securityStatus', 'error', result.message || '获取设置失败');
          document.getElementById('twoFASwitch').checked = false;
        }
      } catch (e) {
        showStatus('securityStatus', 'error', '网络错误: ' + e.message);
        document.getElementById('twoFASwitch').checked = false;
      }
    }
  }

  async function rebind2FA() {
    const input = prompt('请输入恢复码以重新绑定二步验证：');
    if (!input) return;
    const recoveryCode = input.trim().toUpperCase();

    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/totp/rebind`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ recoveryCode })
      });
      if (result.code === 0 && result.data.secret) {
        setupSecret = result.data.secret;
        document.getElementById('setupSecret').value = result.data.manualCode;
        document.getElementById('setupQrContainer').innerHTML = `<img src="${result.data.qrCodeUrl}" alt="二维码">`;
        document.getElementById('twoFAActions').classList.add('hidden');
        document.getElementById('twoFASetup').classList.remove('hidden');
        document.getElementById('twoFASetupTitle').textContent = '重新绑定二步验证';
      } else {
        showStatus('securityStatus', 'error', result.message || '恢复码错误或不可重新绑定');
      }
    } catch (e) {
      showStatus('securityStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function confirmEnable2FA() {
    const otp = document.getElementById('verifyOtp').value.trim();
    if (!otp || otp.length !== 6) {
      showStatus('securityStatus', 'error', '请输入6位验证码');
      return;
    }

    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/totp/enable`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ secret: setupSecret, otp })
      });

      if (result.code === 0) {
        showStatus('securityStatus', 'success', '二步验证已启用');
        document.getElementById('twoFASetup').classList.add('hidden');
        document.getElementById('twoFAActions').classList.remove('hidden');
        loadSecurityStatus();

        const codesList = document.getElementById('recoveryCodesList');
        if (codesList) {
          codesList.innerHTML = result.data.recoveryCodes.map(c => `<div class="code">${c}</div>`).join('');
          document.getElementById('showRecoveryCodes').classList.remove('hidden');
        }
      } else {
        showStatus('securityStatus', 'error', result.message || '启用失败');
      }
    } catch (e) {
      showStatus('securityStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function disable2FA() {
    const input = prompt('请输入二步验证验证码或恢复码：');
    if (!input) return;
    const value = input.trim();
    // 6 位纯数字视为验证码，其余按恢复码处理
    const isOtp = /^\d{6}$/.test(value);
    const body = isOtp ? { otp: value } : { recoveryCode: value.toUpperCase() };

    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/totp/disable`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });

      if (result.code === 0) {
        showStatus('securityStatus', 'success', '二步验证已禁用');
        loadSecurityStatus();
      } else {
        showStatus('securityStatus', 'error', result.message || '禁用失败');
      }
    } catch (e) {
      showStatus('securityStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function regenerateRecoveryCodes() {
    const input = prompt('请输入二步验证验证码或恢复码：');
    if (!input) return;
    const value = input.trim();
    // 6 位纯数字视为验证码，其余按恢复码处理
    const isOtp = /^\d{6}$/.test(value);
    const body = isOtp ? { otp: value } : { recoveryCode: value.toUpperCase() };

    try {
      const result = await fetchWithSession(`${API_BASE}/api/admin/totp/regenerate-recovery`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });

      if (result.code === 0) {
        alert('恢复码已重新生成：\n' + result.data.recoveryCodes.join('\n'));
        showStatus('securityStatus', 'success', '恢复码已重新生成');
      } else {
        showStatus('securityStatus', 'error', result.message || '操作失败');
      }
    } catch (e) {
      showStatus('securityStatus', 'error', '网络错误: ' + e.message);
    }
  }

  async function checkHealth() {
    try {
      const result = await fetch(`${API_BASE}/health`);
      const data = await result.json();
      document.getElementById('statusJson').textContent = JSON.stringify(data, null, 2);
      showStatus('healthStatus', 'success', '服务运行正常');
    } catch (e) {
      showStatus('healthStatus', 'error', '服务异常: ' + e.message);
    }
  }

  async function checkVersionAPI() {
    try {
      const result = await fetch(`${API_BASE}/api/version/check?version=1.0.0&build=1`);
      const data = await result.json();
      document.getElementById('statusJson').textContent = JSON.stringify(data, null, 2);
      showStatus('healthStatus', 'success', '版本接口正常');
    } catch (e) {
      showStatus('healthStatus', 'error', '版本接口异常: ' + e.message);
    }
  }

  function toggleForceFields(prefix, show) {
    const el = document.getElementById('forceUpdateFields');
    if (el) el.classList.toggle('hidden', !show);
  }

  // data-action 到处理函数的映射（IIFE 内函数不在 window 上）
  const actions = {
    handleLogin,
    verifyOTP,
    useRecoveryCode,
    backToOTP,
    verifyRecoveryCode,
    showSetup2FA,
    cancelSetup,
    enable2FA,
    finishSetup,
    copyRecoveryCodes,
    logout,
    saveVersion,
    loadVersion,
    rebind2FA,
    regenerateRecoveryCodes,
    disable2FA,
    confirmEnable2FA,
    checkHealth,
    checkVersionAPI
  };

  document.addEventListener('DOMContentLoaded', () => {
    // 统一绑定 data-action 按钮（替代内联 onclick，满足 CSP script-src 'self'）
    document.querySelectorAll('[data-action]').forEach(btn => {
      const fn = actions[btn.dataset.action];
      if (typeof fn === 'function') {
        btn.addEventListener('click', fn);
      }
    });
    // tab 切换
    document.querySelectorAll('.tab-bar .tab').forEach(tab => {
      tab.addEventListener('click', () => switchTab(tab.dataset.tab));
    });
    // 强制更新字段显隐
    const vForceUpdate = document.getElementById('v_forceUpdate');
    if (vForceUpdate) {
      vForceUpdate.addEventListener('change', (e) => {
        toggleForceFields('v', e.target.checked);
      });
    }
    // 二步验证开关
    const twoFASwitch = document.getElementById('twoFASwitch');
    if (twoFASwitch) {
      twoFASwitch.addEventListener('change', toggleTwoFA);
    }
    // 初始状态
    document.getElementById('step1').classList.remove('hidden');
    document.getElementById('step2').classList.add('hidden');
    document.getElementById('setup2FA').classList.add('hidden');
    document.getElementById('recoveryCodeSection').classList.add('hidden');
    document.getElementById('mainSection').classList.add('hidden');
    document.getElementById('loginSection').classList.remove('hidden');
    // 回车键支持
    document.getElementById('tokenInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleLogin();
    });
    document.getElementById('otpInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') verifyOTP();
    });
  });
})();
