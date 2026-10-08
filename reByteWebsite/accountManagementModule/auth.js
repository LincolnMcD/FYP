/**
 * ReByte Auth & Session Management Service
 * accountManagementModule
 */

const API_BASE_URL = 'http://localhost:3000';

const ReByteAuth = {
  // Key for storing active user session
  SESSION_KEY: 'rebyte_current_user',
  PASSWORD_CHANGE_KEY: 'rebyte_password_change_in_progress',

  beginPasswordChange() {
    localStorage.setItem(this.PASSWORD_CHANGE_KEY, String(Date.now()));
  },

  endPasswordChange() {
    localStorage.removeItem(this.PASSWORD_CHANGE_KEY);
  },

  isPasswordChangeInProgress() {
    const startedAt = Number(localStorage.getItem(this.PASSWORD_CHANGE_KEY) || 0);
    if (!startedAt) return false;
    if (Date.now() - startedAt > 120000) {
      this.endPasswordChange();
      return false;
    }
    return true;
  },

  /**
   * Get currently logged-in user profile
   */
  getUser() {
    try {
      const data = localStorage.getItem(this.SESSION_KEY);
      return data ? JSON.parse(data) : null;
    } catch (e) {
      console.error('Error reading session:', e);
      return null;
    }
  },

  /**
   * Save user session
   */
  setUser(userData) {
    try {
      localStorage.setItem(this.SESSION_KEY, JSON.stringify(userData));
    } catch (e) {
      console.error('Error saving session:', e);
    }
  },

  /**
   * Clear user session and notify
   */
  logout() {
    let confirmModal = document.getElementById('logoutConfirmModal');
    if (!confirmModal) {
      confirmModal = document.createElement('div');
      confirmModal.id = 'logoutConfirmModal';
      confirmModal.className = 'modal-backdrop';
      confirmModal.innerHTML = `
        <div class="modal-card" style="text-align: center; padding: 32px 24px; max-width: 320px;">
          <div style="width: 56px; height: 56px; background-color: #fee2e2; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 16px;">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><polyline points="16 17 21 12 16 7"></polyline><line x1="21" y1="12" x2="9" y2="12"></line></svg>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #0f172a; margin-bottom: 8px;">Sign Out?</h3>
          <p style="font-size: 14px; color: #64748b; margin-bottom: 24px;">Are you sure you want to sign out of your ReByte account?</p>
          <div style="display: flex; gap: 12px; width: 100%;">
            <button id="cancelLogoutBtn" style="flex: 1; padding: 12px; border: 1px solid #cbd5e1; background: transparent; border-radius: 8px; font-weight: 600; color: #475569; cursor: pointer;">Cancel</button>
            <button id="confirmLogoutBtn" style="flex: 1; padding: 12px; background-color: #ef4444; border: none; border-radius: 8px; font-weight: 600; color: white; cursor: pointer;">Sign Out</button>
          </div>
        </div>
      `;
      document.body.appendChild(confirmModal);

      document.getElementById('cancelLogoutBtn').addEventListener('click', () => {
        confirmModal.classList.remove('show');
      });

      document.getElementById('confirmLogoutBtn').addEventListener('click', () => {
        confirmModal.classList.remove('show');
        localStorage.removeItem(this.SESSION_KEY);
        this.showToast('You have been signed out successfully.', 'info');
        setTimeout(() => {
          window.location.href = '/index.html';
        }, 600);
      });
    }
    
    // Force reflow and show
    void confirmModal.offsetWidth;
    confirmModal.classList.add('show');
  },

  /**
   * Check if user is authenticated
   */
  isLoggedIn() {
    return this.getUser() !== null;
  },

  /**
   * Initialize header navbar:
   * If logged in -> show profile icon with dropdown menu
   * If NOT logged in -> show Login and Register buttons directly (no welcome page needed)
   */
  initHeader() {
    const headerActions = document.querySelector('.header-actions');
    const user = this.getUser();

    if (headerActions) {
      if (user) {
        const initial = (user.name || user.email || 'U').charAt(0).toUpperCase();
        headerActions.innerHTML = `
          <a href="profile.html" class="profile-button logged-in" id="profileNavBtn" aria-label="User Account" title="Logged in as ${user.name || user.email}" style="background-color: #e2e8f0; color: #64748b; text-decoration: none; display: flex; align-items: center; justify-content: center; width: 40px; height: 40px; border-radius: 50%;">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>
          </a>
        `;
      } else {
        // NOT logged in: Direct Login and Register buttons
        headerActions.innerHTML = `
          <a href="register.html" class="btn-nav-register">Register</a>
          <a href="login.html" class="btn-nav-login">
            Login
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>
          </a>
        `;
      }
    }

    // Set active link in navbar
    const currentPath = window.location.pathname.toLowerCase();
    const navLinks = document.querySelectorAll('.nav-item');
    navLinks.forEach(item => {
      const link = item.querySelector('a');
      if (link) {
        const href = link.getAttribute('href')?.toLowerCase();
        if (href && (currentPath.endsWith(href) || (href === 'home.html' && (currentPath.endsWith('/') || currentPath.endsWith('index.html'))))) {
          navLinks.forEach(n => n.classList.remove('active'));
          item.classList.add('active');
        }
      }
    });
  },

  /**
   * Exact Email validation logic matching rebyte_mobile & backend/validation.js
   */
  validateEmail(email) {
    if (!email || email.length === 0) return { isValid: false, message: 'Email cannot be empty' };
    if (email.includes(' ')) return { isValid: false, message: 'Email cannot contain spaces' };
    if (/[A-Z]/.test(email)) return { isValid: false, message: 'Email cannot contain capital letters' };

    if (!email.includes('@')) return { isValid: false, message: 'Email must contain @' };

    const parts = email.split('@');
    if (parts.length > 2) return { isValid: false, message: 'Email cannot contain multiple @' };

    const beforeAt = parts[0];
    const afterAt = parts[1];

    if (beforeAt.length < 1) return { isValid: false, message: 'Email must have at least 1 character before @' };

    if (!afterAt.includes('.')) return { isValid: false, message: 'Email must have a dot after @' };

    const afterParts = afterAt.split('.');
    if (afterParts.length !== 2) return { isValid: false, message: 'Email must have exactly one dot after @' };

    const betweenAtAndDot = afterParts[0];
    const afterDot = afterParts[1];

    if (betweenAtAndDot.length < 1) return { isValid: false, message: 'Email must have at least 1 character between @ and .' };
    if (afterDot.length < 1) return { isValid: false, message: 'Email must have at least 1 character after .' };

    return { isValid: true, message: '' };
  },

  /**
   * Exact Password validation logic matching rebyte_mobile & backend/validation.js
   */
  validatePassword(password) {
    if (!password || password.trim() === '') return { isValid: false, message: 'Please enter a password' };
    if (password.length < 8) return { isValid: false, message: 'Password must be at least 8 characters' };
    if (!/[A-Z]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 uppercase letter' };
    if (!/[a-z]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 lowercase letter' };
    if (!/[0-9]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 number' };
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 special character' };

    return { isValid: true, message: '' };
  },

  /**
   * Password criteria check breakdown for real-time checklist indicators
   */
  checkPasswordCriteria(pwd) {
    return {
      length: pwd.length >= 8,
      uppercase: /[A-Z]/.test(pwd),
      lowercase: /[a-z]/.test(pwd),
      number: /[0-9]/.test(pwd),
      special: /[!@#$%^&*(),.?":{}|<>]/.test(pwd)
    };
  },

  /**
   * Confirm password validation matching rebyte_mobile
   */
  validateConfirmPassword(password, confirmPassword) {
    if (!confirmPassword || confirmPassword.trim() === '') return { isValid: false, message: 'Please confirm your password' };
    if (password !== confirmPassword) return { isValid: false, message: 'Passwords do not match' };

    return { isValid: true, message: '' };
  },

  validatePhoneNumber(phoneNumber) {
    const digits = String(phoneNumber || '').replace(/\D/g, '');
    if (!digits) return { isValid: false, message: 'Phone number is required' };
    if (!digits.startsWith('1')) return { isValid: false, message: 'Malaysian mobile numbers must start with 1' };
    const expectedLength = digits.startsWith('11') ? 10 : 9;
    if (digits.length !== expectedLength) {
      return { isValid: false, message: `This mobile number needs ${expectedLength} digits after +60` };
    }
    return { isValid: true, message: '' };
  },

  /**
   * Display top toast notification banner (exact mobile _showTopToast match)
   */
  showToast(message, type = 'info') {
    let toast = document.getElementById('globalToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'globalToast';
      document.body.appendChild(toast);
    }

    const iconSvg = type === 'error'
      ? `<svg class="toast-banner-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>`
      : (type === 'success'
        ? `<svg class="toast-banner-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>`
        : `<svg class="toast-banner-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>`);

    toast.className = `toast-banner ${type}`;
    toast.innerHTML = `
      ${iconSvg}
      <span class="toast-banner-text">${message}</span>
      <button class="toast-banner-close" aria-label="Dismiss toast" onclick="this.parentElement.classList.remove('show')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
      </button>
    `;

    // Force animation frame
    void toast.offsetWidth;
    toast.classList.add('show');

    if (this._toastTimer) clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => {
      toast.classList.remove('show');
    }, 6000);
  },

  /**
   * Initialize Firebase Client SDK for web OAuth
   */
  initFirebase() {
    if (typeof firebase !== 'undefined' && !firebase.apps.length) {
      firebase.initializeApp({
        apiKey: "AIzaSyA8MQf-isqvndby6N6k2bfbD-KagiawFNE",
        authDomain: "rebyte-12549.firebaseapp.com",
        projectId: "rebyte-12549",
        storageBucket: "rebyte-12549.firebasestorage.app",
        messagingSenderId: "1013924601244"
      });
    }
  },

  /**
   * Email login handler (Connects strictly to real backend / Firebase, exact mobile match)
   */
  async login(email, password) {
    // 1. Frontend format validation
    const emailVal = this.validateEmail(email);
    if (!emailVal.isValid) {
      return { success: false, error: emailVal.message, field: 'email' };
    }
    if (!password || password.trim() === '') {
      return { success: false, error: 'Password cannot be empty', field: 'password' };
    }

    // 2. Call backend login endpoint
    try {
      const response = await fetch(`${API_BASE_URL}/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, clientType: 'Web' })
      });

      const data = await response.json();
      if (response.ok) {
        const user = {
          email,
          name: data.name || email.split('@')[0],
          role: data.role || 'Customer',
          token: data.token,
          uid: data.uid,
          loginMethod: 'Email'
        };
        if (typeof firebase !== 'undefined' && firebase.auth) {
          try {
            const credential = await firebase.auth().signInWithEmailAndPassword(email, password);
            user.token = await credential.user.getIdToken();
          } catch (authError) {
            console.warn('Could not initialize Firebase session after login:', authError);
          }
        }
        this.setUser(user);
        return { success: true, message: data.message || 'Login successful!', user, role: user.role };
      } else {
        const error = data.error || 'Login failed';
        const normalizedError = error.toLowerCase();
        if (normalizedError.includes('user_disabled') || normalizedError.includes('user-disabled') ||
            (normalizedError.includes('archived') && normalizedError.includes('administrator'))) {
          return { success: false, error: 'This account has been archived. Please contact administrator.' };
        }
        return { success: false, error: error.replace(/contact an administrator/ig, 'contact administrator') };
      }
    } catch (networkErr) {
      console.error('Backend connection error:', networkErr);
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  /**
   * OAuth login submission to backend
   */
  async oauthLogin(idToken, provider, fallbackEmail, displayName) {
    try {
      // To satisfy deferring the creation of the record until Step 3, we first check if the user exists natively:
      if (fallbackEmail) {
        const checkRes = await fetch(`${API_BASE_URL}/get-profile`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: fallbackEmail })
        });
        
        if (checkRes.status === 404) {
          // New OAuth User! Defer backend record creation.
          return {
            success: true,
            requireProfileComplete: true,
            email: fallbackEmail,
            name: displayName || 'ReByte User',
            pendingIdToken: idToken,
            method: provider
          };
        }
      }

      const response = await fetch(`${API_BASE_URL}/oauth-login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          idToken,
          loginMethod: provider,
          clientType: 'Web',
          fallbackEmail
        })
      });

      const data = await response.json();
      if (response.ok) {
        const user = {
          email: data.email,
          name: data.name || 'ReByte User',
          role: data.role || 'Customer',
          token: idToken,
          loginMethod: provider
        };
        this.setUser(user);
        return {
          success: true,
          message: data.message || `Login successful through ${provider}`,
          user,
          role: user.role,
          requireProfileComplete: data.requireProfileComplete
        };
      } else {
        return {
          success: false,
          error: data.error || `${provider} OAuth login failed.`
        };
      }
    } catch (err) {
      console.error('OAuth network error:', err);
      return {
        success: false,
        error: 'Connection failed. Ensure backend server is running.'
      };
    }
  },

  /**
   * Real Google OAuth Login via Firebase Web Client SDK
   */
  async signInWithGoogle() {
    this.initFirebase();
    if (typeof firebase === 'undefined' || !firebase.auth) {
      return { success: false, error: 'Firebase authentication is unavailable.' };
    }

    try {
      const provider = new firebase.auth.GoogleAuthProvider();
      provider.addScope('email');
      provider.setCustomParameters({ prompt: 'select_account' });
      const userCred = await firebase.auth().signInWithPopup(provider);
      console.log('Google Auth userCred:', userCred);
      const idToken = await userCred.user.getIdToken();
      if (!idToken) {
        return { success: false, error: 'Failed to retrieve auth token from Google.' };
      }
      const fallbackEmail = userCred.user.email || (userCred.additionalUserInfo && userCred.additionalUserInfo.profile && userCred.additionalUserInfo.profile.email);
      const displayName = userCred.user.displayName || (userCred.additionalUserInfo && userCred.additionalUserInfo.profile && userCred.additionalUserInfo.profile.name);
      const loginResult = await this.oauthLogin(idToken, 'Google', fallbackEmail, displayName);
      
      // If backend blocks the login, but Firebase just created a new Auth record, delete the ghost record
      if (!loginResult.success && userCred.additionalUserInfo && userCred.additionalUserInfo.isNewUser) {
        try { await userCred.user.delete(); } catch (e) { console.error('Failed to delete ghost user:', e); }
      }
      
      return loginResult;
    } catch (err) {
      console.error('Google Sign In error:', err);
      if (err.code === 'auth/popup-closed-by-user' || err.code === 'auth/cancelled-popup-request') {
        return { success: false, error: 'Google sign in was cancelled.' };
      }
      if (err.code === 'auth/account-exists-with-different-credential') {
        let originalMethod = 'Email/Password';
        if (err.email || (err.customData && err.customData.email)) {
          const targetEmail = err.email || err.customData.email;
          try {
            const methods = await firebase.auth().fetchSignInMethodsForEmail(targetEmail);
            if (methods.includes('password')) originalMethod = 'Email/Password';
            else if (methods.includes('google.com')) originalMethod = 'Google';
            else if (methods.includes('facebook.com')) originalMethod = 'Facebook';
          } catch (e) {}
        }
        return { success: false, error: `This email is already registered. Please sign in using ${originalMethod}.` };
      }
      return { success: false, error: err.message || 'Google sign in failed.' };
    }
  },

  /**
   * Real Facebook OAuth Login via Firebase Web Client SDK
   */
  async signInWithFacebook() {
    this.initFirebase();
    if (typeof firebase === 'undefined' || !firebase.auth) {
      return { success: false, error: 'Firebase authentication is unavailable.' };
    }

    try {
      const provider = new firebase.auth.FacebookAuthProvider();
      provider.addScope('email');
      provider.addScope('public_profile');
      const userCred = await firebase.auth().signInWithPopup(provider);
      console.log('Facebook Auth userCred:', userCred);
      const idToken = await userCred.user.getIdToken();
      if (!idToken) {
        return { success: false, error: 'Failed to retrieve auth token from Facebook.' };
      }
      const fallbackEmail = userCred.user.email || (userCred.additionalUserInfo && userCred.additionalUserInfo.profile && userCred.additionalUserInfo.profile.email);
      const displayName = userCred.user.displayName || (userCred.additionalUserInfo && userCred.additionalUserInfo.profile && userCred.additionalUserInfo.profile.name);
      const loginResult = await this.oauthLogin(idToken, 'Facebook', fallbackEmail, displayName);
      
      // If backend blocks the login, but Firebase just created a new Auth record, delete the ghost record
      if (!loginResult.success && userCred.additionalUserInfo && userCred.additionalUserInfo.isNewUser) {
        try { await userCred.user.delete(); } catch (e) { console.error('Failed to delete ghost user:', e); }
      }
      
      return loginResult;
    } catch (err) {
      console.error('Facebook Sign In error:', err);
      if (err.code === 'auth/popup-closed-by-user' || err.code === 'auth/cancelled-popup-request') {
        return { success: false, error: 'Facebook sign in was cancelled.' };
      }
      if (err.code === 'auth/account-exists-with-different-credential') {
        let originalMethod = 'Email/Password';
        if (err.email || (err.customData && err.customData.email)) {
          const targetEmail = err.email || err.customData.email;
          try {
            const methods = await firebase.auth().fetchSignInMethodsForEmail(targetEmail);
            if (methods.includes('password')) originalMethod = 'Email/Password';
            else if (methods.includes('google.com')) originalMethod = 'Google';
            else if (methods.includes('facebook.com')) originalMethod = 'Facebook';
          } catch (e) {}
        }
        return { success: false, error: `This email is already registered. Please sign in using ${originalMethod}.` };
      }
      if (err.code === 'auth/operation-not-supported-in-this-app' || err.code === 'auth/configuration-not-found') {
        return { success: false, error: 'Facebook Sign In is not enabled in Firebase Console for this app.' };
      }
      return { success: false, error: err.message || 'Facebook sign in failed.' };
    }
  },

  /**
   * Request email verification OTP from backend
   */
  async requestOTP(email) {
    try {
      const response = await fetch(`${API_BASE_URL}/request-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      });
      const data = await response.json();
      if (response.ok) {
        return { success: true, message: data.message || 'Verification code sent.' };
      } else {
        return { success: false, error: data.error || 'Failed to send verification code.' };
      }
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  /**
   * Request password reset OTP from backend
   */
  async requestResetOTP(email) {
    try {
      const response = await fetch(`${API_BASE_URL}/forgot-password/request-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      });
      const data = await response.json();
      if (response.ok) {
        return { success: true, message: data.message || 'Verification code sent.' };
      } else {
        return { success: false, error: data.error || 'Failed to send verification code.' };
      }
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  /**
   * Verify password reset OTP
   */
  async verifyResetOTP(email, otp) {
    try {
      const response = await fetch(`${API_BASE_URL}/forgot-password/verify-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, otp, exchangeForResetToken: true })
      });
      const data = await response.json();
      if (response.ok) {
        if (!data.resetToken) {
          return { success: false, error: 'The password reset service is out of date. Restart the ReByte backend, then verify the code again.' };
        }
        return { success: true, resetToken: data.resetToken, message: data.message || 'OTP is valid.' };
      } else {
        return { success: false, error: data.error || 'Invalid OTP.' };
      }
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  /**
   * Reset Password
   */
  async resetPassword(email, newPassword, resetToken) {
    try {
      const response = await fetch(`${API_BASE_URL}/forgot-password/reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, newPassword, resetToken })
      });
      const data = await response.json();
      if (response.ok) {
        return { success: true, message: data.message || 'Password reset successfully!' };
      } else {
        return { success: false, error: data.error || 'Reset failed.' };
      }
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  /**
   * Registration handler (connects strictly to backend)
   */
  async register(email, password, otp, fullName, phoneNumber, gender, birthDate) {
    try {
      const response = await fetch(`${API_BASE_URL}/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, otp, fullName, phoneNumber, gender, birthDate })
      });

      const data = await response.json();
      if (response.ok) {
        let token = null;
        if (typeof firebase !== 'undefined' && firebase.auth) {
          try {
            const credential = await firebase.auth().signInWithEmailAndPassword(email, password);
            token = await credential.user.getIdToken();
          } catch (authError) {
            console.warn('Could not initialize Firebase session after registration:', authError);
          }
        }
        this.setUser({
          email,
          name: fullName || email.split('@')[0],
          role: 'Customer',
          token,
          loginMethod: 'Email'
        });
        return { success: true, message: data.message || 'Account created successfully!' };
      } else {
        return { success: false, error: data.error || 'Registration failed' };
      }
    } catch (networkErr) {
      console.error('Registration network error:', networkErr);
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async checkStaffEmail(email) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/check-staff-email`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${user.token}` },
        body: JSON.stringify({ email })
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message } : { success: false, error: data.error || 'Could not check this email.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async registerStaff(staffData) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/register-staff`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${user.token}` },
        body: JSON.stringify(staffData)
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Staff account created successfully.' } : { success: false, error: data.error || 'Staff account creation failed.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async updateStaff(staffId, staffData) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff/${encodeURIComponent(staffId)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${user.token}` },
        body: JSON.stringify(staffData)
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Staff account updated successfully.' } : { success: false, error: data.error || 'Staff account update failed.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async updateOwnStaffProfile(profileData) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your staff session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff-profile`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${user.token}` },
        body: JSON.stringify(profileData)
      });
      const data = await response.json();
      if (!response.ok) return { success: false, error: data.error || 'Could not update staff profile.' };
      this.setUser({ ...user, name: data.profile?.fullName || profileData.fullName });
      return { success: true, message: data.message || 'Staff profile updated successfully.', profile: data.profile };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async getOwnStaffProfile() {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your staff session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff-profile`, {
        headers: { Authorization: `Bearer ${user.token}` }
      });
      const data = await response.json();
      return response.ok ? { success: true, profile: data.profile } : { success: false, error: data.error || 'Could not load staff profile.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async archiveStaff(staffId) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff/${encodeURIComponent(staffId)}/archive`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${user.token}` }
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Staff member archived.' } : { success: false, error: data.error || 'Staff archive failed.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async restoreStaff(staffId) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff/${encodeURIComponent(staffId)}/restore`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${user.token}` }
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Staff member restored.' } : { success: false, error: data.error || 'Staff restore failed.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async deleteStaff(staffId) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/staff/${encodeURIComponent(staffId)}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${user.token}` }
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Staff member permanently deleted.' } : { success: false, error: data.error || 'Staff deletion failed.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async getCustomerList() {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/customer-list`, {
        headers: { Authorization: `Bearer ${user.token}` }
      });
      const data = await response.json();
      return response.ok ? { success: true, data } : { success: false, error: data.error || 'Could not load customer records.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async setCustomerStatus(customerId, status) {
    const user = this.getUser();
    if (!user?.token) return { success: false, error: 'Your admin session has expired. Please sign in again.' };
    try {
      const response = await fetch(`${API_BASE_URL}/customers/${encodeURIComponent(customerId)}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${user.token}` },
        body: JSON.stringify({ status })
      });
      const data = await response.json();
      return response.ok ? { success: true, message: data.message || 'Customer status updated.' } : { success: false, error: data.error || 'Could not update this customer.' };
    } catch (err) {
      return { success: false, error: 'Connection failed. Ensure backend is running.' };
    }
  },

  async checkStaffSession() {
    if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
    const user = this.getUser();
    try {
      let token = user?.token;
      if (!token && typeof firebase !== 'undefined' && firebase.auth) {
        const auth = firebase.auth();
        if (typeof auth.authStateReady === 'function') await auth.authStateReady();
        if (auth.currentUser) token = await auth.currentUser.getIdToken();
      }
      if (!token) return { success: false, error: 'Staff session is missing.' };
      const response = await fetch(`${API_BASE_URL}/staff-session`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
      const data = await response.json();
      return response.ok ? { success: true } : { success: false, archived: data.archived === true, error: data.error || 'Staff session has ended.' };
    } catch (err) {
      if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
      if (err?.code?.startsWith('auth/')) {
        const archived = err.code === 'auth/user-disabled';
        return {
          success: false,
          archived,
          error: archived ? 'This account has been archived. Please contact administrator.' : 'Staff session has ended.'
        };
      }
      return { success: false, transient: true, error: 'Could not verify staff session.' };
    }
  },

  async checkAccountSession() {
    if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
    const user = this.getUser();
    if (!user || user.role !== 'Customer') return { success: true, skipped: true };
    try {
      let token = user.token;
      if (typeof firebase !== 'undefined' && firebase.auth) {
        const currentUser = firebase.auth().currentUser;
        if (currentUser && currentUser.email?.toLowerCase() === user.email?.toLowerCase()) {
          token = await currentUser.getIdToken();
          if (token !== user.token) this.setUser({ ...user, token });
        }
      }
      if (!token) return { success: false, expired: true, error: 'Session expired. Please log in again.' };
      const response = await fetch(`${API_BASE_URL}/account-session`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
      const data = await response.json();
      return response.ok
        ? { success: true }
        : { success: false, expired: data.expired === true || response.status === 401 || response.status === 403, archived: data.archived === true, error: data.error || 'Session expired. Please log in again.' };
    } catch (err) {
      if (this.isPasswordChangeInProgress()) return { success: true, skipped: true };
      if (err?.code?.startsWith('auth/')) {
        const archived = err.code === 'auth/user-disabled';
        return {
          success: false,
          expired: true,
          archived,
          error: archived ? 'This account has been archived. Please contact administrator.' : 'Session expired. Please log in again.'
        };
      }
      return { success: false, transient: true, error: 'Could not verify account session.' };
    }
  },

  forceSessionLogout(archived = false) {
    localStorage.removeItem(this.SESSION_KEY);
    if (typeof firebase !== 'undefined' && firebase.auth) firebase.auth().signOut().catch(() => {});
    const isLoginPage = window.location.pathname.toLowerCase().endsWith('/login.html');
    if (isLoginPage) {
      this.showToast(archived
        ? 'This account has been archived. Please contact administrator.'
        : 'Session expired. Please log in again.', 'error');
      return;
    }
    const loginPath = window.location.pathname.toLowerCase().includes('/staffmodule/')
      ? '../accountManagementModule/login.html'
      : 'login.html';
    window.location.replace(`${loginPath}?${archived ? 'archived=1' : 'sessionExpired=1'}`);
  }
};

// Auto-run header setup on page load
document.addEventListener('DOMContentLoaded', () => {
  ReByteAuth.initHeader();
  ReByteAuth.initFirebase();
  const params = new URLSearchParams(window.location.search);
  if (params.get('sessionExpired') === '1') {
    params.delete('sessionExpired');
    const query = params.toString();
    history.replaceState(null, '', `${window.location.pathname}${query ? `?${query}` : ''}${window.location.hash}`);
    setTimeout(() => ReByteAuth.showToast('Session expired. Please log in again.', 'error'), 100);
  } else if (params.get('archived') === '1') {
    params.delete('archived');
    const query = params.toString();
    history.replaceState(null, '', `${window.location.pathname}${query ? `?${query}` : ''}${window.location.hash}`);
    setTimeout(() => ReByteAuth.showToast('This account has been archived. Please contact administrator.', 'error'), 100);
  }
  let accountSessionCheckInProgress = false;
  const checkActiveSession = async () => {
    if (accountSessionCheckInProgress || !ReByteAuth.isLoggedIn()) return;
    accountSessionCheckInProgress = true;
    try {
      const user = ReByteAuth.getUser();
      if (String(user?.role || '').toLowerCase() === 'staff') {
        const result = await ReByteAuth.checkStaffSession();
        if (!result.success && !result.transient && !result.skipped) {
          ReByteAuth.forceSessionLogout(result.archived === true);
        }
      } else {
        const result = await ReByteAuth.checkAccountSession();
        if (result.expired) ReByteAuth.forceSessionLogout(result.archived === true);
      }
    } finally {
      accountSessionCheckInProgress = false;
    }
  };
  setTimeout(checkActiveSession, 1000);
  window.setInterval(checkActiveSession, 2000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') checkActiveSession();
  });
  window.addEventListener('focus', checkActiveSession);
});
