package com.fitlog.app.ui.exercises

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fitlog.app.ui.ConfirmDeleteDialog
import androidx.lifecycle.viewModelScope
import com.fitlog.app.data.BuiltInExercises
import com.fitlog.app.data.Graph
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.Side
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ExerciseLibraryViewModel : ViewModel() {
    private val repo = Graph.repository
    val exercises: StateFlow<List<Exercise>> = repo.observeExercises()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun add(name: String, group: String, side: Side) = io { repo.addCustomExercise(name, group, side) }
    fun update(ex: Exercise) = io { repo.updateExercise(ex) }
    fun delete(ex: Exercise) = io { repo.deleteExercise(ex) }

    private fun io(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) { block() }
    }
}

@Composable
fun ExerciseLibraryScreen() {
    val vm: ExerciseLibraryViewModel = viewModel()
    val exercises by vm.exercises.collectAsState()

    var showEditor by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Exercise?>(null) }
    var toDelete by remember { mutableStateOf<Exercise?>(null) }
    var reminderFor by remember { mutableStateOf<Exercise?>(null) }

    Scaffold(
        contentWindowInsets = ScaffoldDefaults.contentWindowInsets.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
        topBar = { TopAppBar(title = { Text("动作库") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = { editing = null; showEditor = true }) {
                Icon(Icons.Filled.Add, contentDescription = "新增动作")
            }
        }
    ) { padding ->
        val grouped = exercises.groupBy { it.muscleGroup }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            grouped.forEach { (group, list) ->
                item { Text(group, style = MaterialTheme.typography.titleSmall) }
                items(list, key = { it.id }) { ex ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(ex.name, style = MaterialTheme.typography.titleMedium)
                                if (ex.isBuiltIn) {
                                    Text("内置", style = MaterialTheme.typography.labelSmall)
                                }
                            }
                            IconButton(onClick = { reminderFor = ex }) {
                                Icon(Icons.Filled.Notifications, contentDescription = "提醒设置")
                            }
                            if (!ex.isBuiltIn) {
                                IconButton(onClick = { editing = ex; showEditor = true }) {
                                    Icon(Icons.Filled.Edit, contentDescription = "编辑")
                                }
                                IconButton(onClick = { toDelete = ex }) {
                                    Icon(Icons.Filled.Delete, contentDescription = "删除", tint = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showEditor) {
        ExerciseEditDialog(
            initial = editing,
            onDismiss = { showEditor = false },
            onSave = { name, group, side ->
                if (editing != null) {
                    vm.update(editing!!.copy(name = name, muscleGroup = group, defaultSide = side))
                } else {
                    vm.add(name, group, side)
                }
                showEditor = false
            }
        )
    }

    toDelete?.let { ex ->
        ConfirmDeleteDialog(
            title = "删除动作",
            message = "确定删除「${ex.name}」？\n该动作在训练记录中的历史数据会保留，但动作本身将从动作库移除。",
            onDismiss = { toDelete = null },
            onConfirm = { vm.delete(ex); toDelete = null }
        )
    }

    reminderFor?.let { ex ->
        ReminderDialog(exercise = ex, onDismiss = { reminderFor = null })
    }
}

@Composable
private fun ExerciseEditDialog(
    initial: Exercise?,
    onDismiss: () -> Unit,
    onSave: (name: String, group: String, side: Side) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var group by remember { mutableStateOf(initial?.muscleGroup ?: BuiltInExercises.GROUPS.first()) }
    var side by remember { mutableStateOf(initial?.defaultSide ?: Side.BOTH) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            Button(
                enabled = name.isNotBlank(),
                onClick = { onSave(name.trim(), group, side) }
            ) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
        title = { Text(if (initial == null) "新增动作" else "编辑动作") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("动作名称") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text("肌群", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BuiltInExercises.GROUPS.forEach { g ->
                        SelectChip(g, group == g) { group = g }
                    }
                }
                Text("默认单 / 双边", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SelectChip("左", side == Side.LEFT) { side = Side.LEFT }
                    SelectChip("右", side == Side.RIGHT) { side = Side.RIGHT }
                    SelectChip("双手", side == Side.BOTH) { side = Side.BOTH }
                }
            }
        }
    )
}

@Composable
private fun ReminderDialog(exercise: Exercise, onDismiss: () -> Unit) {
    var enabled by remember { mutableStateOf(true) }
    var threshold by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    LaunchedEffect(exercise.id) {
        val rule = Graph.repository.getRule(exercise.id)
        enabled = rule?.enabled ?: true
        threshold = if (rule != null && rule.thresholdHours > 0) rule.thresholdHours.toString() else ""
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            Button(onClick = {
                val th = threshold.toIntOrNull() ?: 0
                scope.launch {
                    Graph.repository.setExerciseReminder(exercise.id, enabled, if (th > 0) th else null)
                }
                onDismiss()
            }) { Text("保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
        title = { Text("『${exercise.name}』提醒设置") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("启用该动作提醒", modifier = Modifier.weight(1f))
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
                OutlinedTextField(
                    value = threshold,
                    onValueChange = { threshold = it.filter { c -> c.isDigit() } },
                    label = { Text("间隔阈值（小时，留空=用默认）") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "留空表示使用设置里的默认阈值（${Graph.repository.getDefaultThreshold()} 小时）。",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    )
}

@Composable
private fun SelectChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant
    val fg = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Text(label, color = fg, style = MaterialTheme.typography.labelMedium)
    }
}
