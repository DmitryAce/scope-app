from django.shortcuts import render, redirect
from django.contrib.auth import authenticate, login, logout
from django.contrib import messages


def login_view(request):
    """Login page view"""
    # If already logged in, redirect to dashboard
    if request.user.is_authenticated:
        return redirect('scope:dashboard')
    
    if request.method == 'POST':
        username = request.POST.get('username', '').strip()
        password = request.POST.get('password', '')
        remember_me = request.POST.get('remember_me')
        
        user = authenticate(request, username=username, password=password)
        
        if user is not None:
            login(request, user)
            
            # Set session expiry based on "remember me"
            if not remember_me:
                request.session.set_expiry(0)  # Browser close
            
            # Redirect to next URL or dashboard
            next_url = request.GET.get('next', 'scope:dashboard')
            return redirect(next_url)
        else:
            messages.error(request, 'Неверный логин или пароль')
    
    return render(request, 'users/login.html')


def logout_view(request):
    """Logout and redirect to login page"""
    logout(request)
    messages.success(request, 'Вы вышли из аккаунта')
    return redirect('users:login')
