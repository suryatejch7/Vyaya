import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_settings.dart' as models;
import '../services/local_store.dart';
import 'expense_provider.dart';

class UserProvider extends ChangeNotifier {
  models.User? _currentUser;
  models.UserSettings? _userSettings;
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasLoadedFromStorage = false;

  models.User? get currentUser => _currentUser;
  models.UserSettings? get userSettings => _userSettings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  int get userId => _currentUser?.id ?? 0;
  String get userName => _currentUser?.userName ?? '';
  Future<void> loadUserFromStorage() async {
    if (_hasLoadedFromStorage) {
      return;
    }
    _hasLoadedFromStorage = true;
    _isLoading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      
      if (userId != null && userId > 0) {
        final user = await LocalStore.getUserById(userId);
        if (user != null) {
          _currentUser = user;
          _userSettings = await LocalStore.getUserSettings(userId: userId);
        } else {
          await clearUser();
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load user: $e';
      await clearUser();
    } finally {
      _isLoading = false;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }
  Future<bool> registerUser(String userName) async {
    _setLoading(true);
    _errorMessage = null;
    
    try {
      final exists = await LocalStore.isUsernameTaken(userName);
      if (exists) {
        _errorMessage = 'Username already exists';
        return false;
      }
      final user = await LocalStore.createUser(userName);
      final settings = await LocalStore.createDefaultUserSettings(user.id);
      await _saveUserToStorage(user);
      _currentUser = user;
      _userSettings = settings;
      notifyListeners();
      
      return true;
    } catch (e) {
      _errorMessage = 'Registration failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }
  Future<bool> loginWithUsername(String userName) async {
    _setLoading(true);
    _errorMessage = null;
    
    try {
      final user = await LocalStore.getUserByUsername(userName);
      if (user == null) {
        _errorMessage = 'User not found';
        return false;
      }
      final settings = await LocalStore.getUserSettings(userId: user.id);
      await _saveUserToStorage(user);
      _currentUser = user;
      _userSettings = settings;
      notifyListeners();
      
      return true;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }
  Future<bool> loginWithUserId(int userId) async {
    _setLoading(true);
    _errorMessage = null;
    
    try {
      final user = await LocalStore.getUserById(userId);
      if (user == null) {
        _errorMessage = 'User not found';
        return false;
      }
      final settings = await LocalStore.getUserSettings(userId: user.id);
      await _saveUserToStorage(user);
      _currentUser = user;
      _userSettings = settings;
      notifyListeners();
      
      return true;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }
  Future<void> updateUserSettings(models.UserSettings settings) async {
    try {
      await LocalStore.saveUserSettings(settings);
      _userSettings = settings;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to update settings: $e';
      throw Exception(_errorMessage);
    }
  }
  Future<bool> updateUserName(String userName) async {
    if (_currentUser == null) {
      _errorMessage = 'No user logged in';
      return false;
    }
    
    try {
      
      await LocalStore.updateUserName(userName, userId: _currentUser!.id);
      _currentUser = models.User(
        id: _currentUser!.id,
        userName: userName,
        createdAt: _currentUser!.createdAt,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update username: $e';
      return false;
    }
  }
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    
    _currentUser = null;
    _userSettings = null;
    _errorMessage = null;
    _hasLoadedFromStorage = false; // Reset flag to allow loading from storage again
    notifyListeners();
  }
  Future<void> initializeExpenseProvider(ExpenseProvider expenseProvider) async {
    if (_currentUser != null && _userSettings != null) {
      await expenseProvider.initializeWithUser(
        _currentUser!.id,
        _currentUser!.userName,
        _userSettings!,
      );
    }
  }
  Future<List<models.User>> getAllUsers() async {
    try {
      final users = await LocalStore.getAllUsers();
      return users;
    } catch (e) {
      _errorMessage = 'Failed to fetch users: $e';
      return [];
    }
  }
  bool get isLoggedIn => _currentUser != null;
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Future<void> _saveUserToStorage(models.User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', user.id);
    await prefs.setString('userName', user.userName);
  }
}
