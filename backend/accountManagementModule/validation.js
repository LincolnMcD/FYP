function validateEmail(email) {
  if (!email || email.trim() === '') return { isValid: false, message: 'Email cannot be empty' };
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
}

function validatePassword(password) {
  if (!password || password.length < 8) return { isValid: false, message: 'Password must be at least 8 characters' };
  if (!/[A-Z]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 uppercase letter' };
  if (!/[a-z]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 lowercase letter' };
  if (!/[0-9]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 number' };
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return { isValid: false, message: 'Password must contain at least 1 special character' };
  
  return { isValid: true, message: '' };
}

module.exports = {
  validateEmail,
  validatePassword
};
