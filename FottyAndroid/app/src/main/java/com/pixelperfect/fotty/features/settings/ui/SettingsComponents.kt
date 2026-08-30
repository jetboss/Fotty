package com.pixelperfect.fotty.features.settings.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

@Composable
fun PreferenceCategory(
    title: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    )
}

@Composable
fun SwitchPreference(
    title: String,
    summary: String,
    icon: ImageVector?,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(summary) },
        leadingContent = icon?.let {
            { Icon(it, contentDescription = null) }
        },
        trailingContent = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange
            )
        },
        modifier = modifier.clickable { onCheckedChange(!checked) }
    )
}

@Composable
fun ActionPreference(
    title: String,
    summary: String,
    icon: ImageVector?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = if (summary.isNotEmpty()) {
            { Text(summary) }
        } else null,
        leadingContent = icon?.let {
            { Icon(it, contentDescription = null) }
        },
        modifier = modifier.clickable(onClick = onClick)
    )
}

@Composable
fun <T> ListPreference(
    title: String,
    summary: String,
    icon: ImageVector?,
    value: T,
    options: List<Pair<T, String>>,
    onValueChange: (T) -> Unit,
    showDialog: Boolean,
    onShowDialogChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(summary) },
        leadingContent = icon?.let {
            { Icon(it, contentDescription = null) }
        },
        modifier = modifier.clickable { onShowDialogChange(true) }
    )

    if (showDialog) {
        AlertDialog(
            onDismissRequest = { onShowDialogChange(false) },
            title = { Text(title) },
            text = {
                Column(modifier = Modifier.fillMaxWidth()) {
                    options.forEach { (optionValue, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    onValueChange(optionValue)
                                    onShowDialogChange(false)
                                }
                                .padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = optionValue == value,
                                onClick = null
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(label)
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { onShowDialogChange(false) }) {
                    Text("Cancel")
                }
            }
        )
    }
}
