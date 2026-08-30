package com.pixelperfect.fotty.features.auth.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixelperfect.fotty.features.auth.viewmodel.AuthViewModel
import com.pixelperfect.fotty.core.theme.*

@Composable
fun LoginScreen(
    viewModel: AuthViewModel,
    onLoginSuccess: () -> Unit
) {
    if (viewModel.session != null || viewModel.isGuest) {
        onLoginSuccess()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Fotty",
                style = Typography.titleLarge.copy(fontSize = 48.sp, fontWeight = FontWeight.Bold),
                color = Accent
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                text = if (viewModel.isSignupMode) "Create your account." else "Join the global arena.",
                style = Typography.bodyLarge,
                color = TextSecondary
            )

            Spacer(modifier = Modifier.height(32.dp))

            if (viewModel.isSignupMode) {
                // Name field
                OutlinedTextField(
                    value = viewModel.name,
                    onValueChange = { viewModel.name = it },
                    label = { Text("Display Name", color = TextTertiary) },
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Glass),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Accent,
                        unfocusedBorderColor = Color.Transparent,
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextPrimary
                    ),
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Email field
            OutlinedTextField(
                value = viewModel.email,
                onValueChange = { viewModel.email = it },
                label = { Text("Email", color = TextTertiary) },
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Glass),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Accent,
                    unfocusedBorderColor = Color.Transparent,
                    focusedTextColor = TextPrimary,
                    unfocusedTextColor = TextPrimary
                ),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Password field
            OutlinedTextField(
                value = viewModel.password,
                onValueChange = { viewModel.password = it },
                label = { Text("Password", color = TextTertiary) },
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Glass),
                visualTransformation = PasswordVisualTransformation(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Accent,
                    unfocusedBorderColor = Color.Transparent,
                    focusedTextColor = TextPrimary,
                    unfocusedTextColor = TextPrimary
                ),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(24.dp))

            if (viewModel.error != null) {
                Text(text = viewModel.error!!, color = Error, fontSize = 13.sp)
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Action Button (Login / Signup)
            Button(
                onClick = { 
                    if (viewModel.isSignupMode) viewModel.signUp() else viewModel.signIn()
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Accent),
                shape = RoundedCornerShape(12.dp)
            ) {
                if (viewModel.isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White)
                } else {
                    Text(
                        if (viewModel.isSignupMode) "Create Account" else "Enter Arena",
                        fontSize = 16.sp, 
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Toggle Signup/Login
            Text(
                text = if (viewModel.isSignupMode) "Already have an account? Log In" else "Don't have an account? Sign Up",
                style = Typography.bodyMedium.copy(color = Accent, fontWeight = FontWeight.Medium),
                modifier = Modifier.clickable { viewModel.isSignupMode = !viewModel.isSignupMode }
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Continue as Guest
            OutlinedButton(
                onClick = { viewModel.continueAsGuest() },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                border = null,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = TextSecondary),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text("Continue as Guest", fontSize = 15.sp)
            }
        }
    }
}
