package com.fitlog.app.ui.train

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import com.fitlog.app.data.Graph
import com.fitlog.app.data.model.DayDetail
import com.fitlog.app.data.model.DayExerciseUi
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.SetRecord
import com.fitlog.app.data.model.Side
import com.fitlog.app.ui.ConfirmDeleteDialog
import com.fitlog.app.ui.theme.FitLogTheme
import com.fitlog.app.util.DateUtils
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.combine

class TrainViewModel : ViewModel() {
    private val repo = Graph.repository

    private val _date = MutableStateFlow(DateUtils.todayStr())
    val date: StateFlow<String> = _date.asStateFlow()

    val exercises: StateFlow<List<Exercise>> = repo.observeExercises()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val day: StateFlow<DayDetail?> = _date.flatMapLatest { repo.observeDay(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    fun changeDate(deltaDays: Long) {
        _date.value = DateUtils.plusDays(_date.value, deltaDays)
    }

    fun goToday() {
        _date.value = DateUtils.todayStr()
    }

    fun goToDate(date: String) {
        _date.value = date
    }

    val trainedDates: StateFlow<Set<String>> = repo.observeTrainedDates()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptySet())

    fun addExercise(exerciseId: String) = io { repo.addExerciseToDay(_date.value, exerciseId) }
    fun addSet(sessionExerciseId: String, defaultSide: Side) = io { repo.addSet(sessionExerciseId, defaultSide) }
    fun updateSet(set: SetRecord) = io { repo.updateSet(set) }
    fun deleteSet(set: SetRecord) = io { repo.deleteSet(set) }
    fun deleteExercise(se: com.fitlog.app.data.model.SessionExercise) = io { repo.deleteExerciseFromDay(se) }
    fun updateNote(note: String) = io { repo.updateSessionNote(_date.value, note) }

    private fun io(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) { block() }
    }
}

fun sideLabel(side: Side): String = when (side) {
    Side.LEFT -> "左"
    Side.RIGHT -> "右"
    Side.BOTH -> "双手"
}

@Composable
fun TrainScreen() {
    val vm: TrainViewModel = viewModel()
    val date by vm.date.collectAsState()
    val day by vm.day.collectAsState()
    val exercises by vm.exercises.collectAsState()

    var showAdd by remember { mutableStateOf(false) }
    var editingSet by remember { mutableStateOf<SetRecord?>(null) }
    var pendingDeleteSet by remember { mutableStateOf<SetRecord?>(null) }
    var pendingDeleteExercise by remember { mutableStateOf<DayExerciseUi?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("训练记录") },
                actions = {
                    IconButton(onClick = { vm.changeDate(-1) }) {
                        Icon(Icons.Filled.ChevronLeft, contentDescription = "前一天")
                    }
                    Text(DateUtils.displayFull(date), style = MaterialTheme.typography.titleMedium)
                    IconButton(onClick = { vm.changeDate(1) }) {
                        Icon(Icons.Filled.ChevronRight, contentDescription = "后一天")
                    }
                    TextButton(onClick = { vm.goToday() }) { Text("今天") }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showAdd = true }) {
                Icon(Icons.Filled.Add, contentDescription = "添加动作")
            }
        }
    ) { padding ->
        val items = day?.items ?: emptyList()
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            TrainCalendar(vm)
            Spacer(Modifier.height(8.dp))
            if (items.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize().weight(1f),
                    contentAlignment = Alignment.Center
                ) {
                    Text("这一天还没有训练记录\n点击右下角 + 添加动作", style = MaterialTheme.typography.bodyLarge)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().weight(1f),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(items, key = { it.sessionExercise.id }) { item ->
                        DayExerciseCard(
                            item = item,
                            onAddSet = { vm.addSet(item.sessionExercise.id, item.exercise.defaultSide) },
                            onEditSet = { editingSet = it },
                            onDeleteSet = { pendingDeleteSet = it },
                            onDeleteExercise = { pendingDeleteExercise = item }
                        )
                    }
                }
            }
        }
    }

    if (showAdd) {
        AddExerciseDialog(
            exercises = exercises,
            onDismiss = { showAdd = false },
            onPick = { ex ->
                vm.addExercise(ex.id)
                showAdd = false
            }
        )
    }

    editingSet?.let { set ->
        SetEditDialog(
            set = set,
            onDismiss = { editingSet = null },
            onSave = { updated ->
                vm.updateSet(updated)
                editingSet = null
            },
            onDelete = {
                editingSet = null
                pendingDeleteSet = set
            }
        )
    }

    pendingDeleteSet?.let { set ->
        ConfirmDeleteDialog(
            message = "确定删除「第 ${set.setIndex} 组 · ${formatWeight(set.weight)}kg × ${set.reps}次」吗？\n删除后无法恢复。",
            onDismiss = { pendingDeleteSet = null },
            onConfirm = {
                vm.deleteSet(set)
                pendingDeleteSet = null
            }
        )
    }

    pendingDeleteExercise?.let { item ->
        ConfirmDeleteDialog(
            message = "确定删除动作「${item.exercise.name}」及其全部 ${item.sets.size} 组记录吗？\n删除后无法恢复。",
            onDismiss = { pendingDeleteExercise = null },
            onConfirm = {
                vm.deleteExercise(item.sessionExercise)
                pendingDeleteExercise = null
            }
        )
    }
}

@Composable
private fun TrainCalendar(vm: TrainViewModel) {
    val date by vm.date.collectAsState()
    val trained by vm.trainedDates.collectAsState()
    var expanded by remember { mutableStateOf(false) }
    var displayMonth by remember { mutableStateOf(date) }

    // 外部切换日期（翻页/今天）时，同步月历显示月份
    LaunchedEffect(date) { displayMonth = date }

    val firstStr = DateUtils.toStr(DateUtils.firstOfMonth(displayMonth))
    val lead = DateUtils.weekdayMondayFirst(firstStr) - 1 // 周一为第一列
    val days = DateUtils.lengthOfMonth(displayMonth)
    val total = lead + days

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { displayMonth = DateUtils.plusMonths(displayMonth, -1) }) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = "上个月")
                }
                Text(
                    DateUtils.yearMonthLabel(displayMonth),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center
                )
                IconButton(onClick = { displayMonth = DateUtils.plusMonths(displayMonth, 1) }) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = "下个月")
                }
                IconButton(onClick = { expanded = !expanded }) {
                    Icon(
                        if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                        contentDescription = "展开/收起日历"
                    )
                }
            }

            if (expanded) {
                Spacer(Modifier.height(8.dp))
                Row {
                    listOf("一", "二", "三", "四", "五", "六", "日").forEach { w ->
                        Text(
                            w,
                            modifier = Modifier.weight(1f),
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
                Spacer(Modifier.height(4.dp))

                val cells: List<String?> = (0 until total).map { i ->
                    if (i < lead) null else DateUtils.plusDays(firstStr, (i - lead).toLong())
                }
                cells.chunked(7).forEach { week ->
                    Row(modifier = Modifier.fillMaxWidth()) {
                        repeat(7) { col ->
                            val d = week.getOrNull(col)
                            Box(
                                modifier = Modifier.weight(1f).padding(2.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                if (d != null) {
                                    val isTrained = trained.contains(d)
                                    val isSelected = d == date
                                    val bg = when {
                                        isSelected -> MaterialTheme.colorScheme.primary
                                        isTrained -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.22f)
                                        else -> Color.Transparent
                                    }
                                    Box(
                                        modifier = Modifier
                                            .size(36.dp)
                                            .clip(CircleShape)
                                            .background(bg)
                                            .clickable {
                                                vm.goToDate(d)
                                                expanded = false
                                            },
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(
                                            DateUtils.dayOfMonth(d).toString(),
                                            color = if (isSelected) MaterialTheme.colorScheme.onPrimary
                                            else MaterialTheme.colorScheme.onSurface,
                                            style = MaterialTheme.typography.labelMedium
                                        )
                                        if (isTrained && !isSelected) {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxSize()
                                                    .padding(bottom = 4.dp),
                                                contentAlignment = Alignment.BottomCenter
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(4.dp)
                                                        .clip(CircleShape)
                                                        .background(MaterialTheme.colorScheme.secondary)
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier.size(10.dp).clip(CircleShape)
                            .background(MaterialTheme.colorScheme.secondary)
                    )
                    Text("练过", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun DayExerciseCard(
    item: DayExerciseUi,
    onAddSet: () -> Unit,
    onEditSet: (SetRecord) -> Unit,
    onDeleteSet: (SetRecord) -> Unit,
    onDeleteExercise: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(item.exercise.name, style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.width(8.dp))
                GroupChip(item.exercise.muscleGroup)
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onDeleteExercise) {
                    Icon(Icons.Filled.Delete, contentDescription = "删除动作", tint = MaterialTheme.colorScheme.error)
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            item.sets.forEach { s ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("第${s.setIndex}组", style = MaterialTheme.typography.bodyMedium)
                    Spacer(Modifier.width(12.dp))
                    Text("${formatWeight(s.weight)}kg", style = MaterialTheme.typography.bodyLarge)
                    Spacer(Modifier.width(12.dp))
                    Text("${s.reps}次", style = MaterialTheme.typography.bodyLarge)
                    Spacer(Modifier.width(8.dp))
                    Text(sideLabel(s.side), style = MaterialTheme.typography.labelMedium)
                    s.rpe?.let {
                        Spacer(Modifier.width(8.dp))
                        Text("RPE $it", style = MaterialTheme.typography.labelMedium)
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { onEditSet(s) }) {
                        Icon(Icons.Filled.Edit, contentDescription = "编辑")
                    }
                    IconButton(onClick = { onDeleteSet(s) }) {
                        Icon(Icons.Filled.Delete, contentDescription = "删除组", tint = MaterialTheme.colorScheme.error)
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = onAddSet, modifier = Modifier.fillMaxWidth()) {
                Text("+ 加一组")
            }
        }
    }
}

@Composable
private fun GroupChip(text: String) {
    Box(
        modifier = Modifier
            .clip(MaterialTheme.shapes.small)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 8.dp, vertical = 2.dp)
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall)
    }
}

fun formatWeight(w: Float): String = if (w % 1 == 0f) w.toInt().toString() else w.toString()

@Composable
private fun AddExerciseDialog(
    exercises: List<Exercise>,
    onDismiss: () -> Unit,
    onPick: (Exercise) -> Unit
) {
    var query by remember { mutableStateOf("") }
    val filtered = remember(exercises, query) {
        if (query.isBlank()) exercises else exercises.filter {
            it.name.contains(query, ignoreCase = true) || it.muscleGroup.contains(query, ignoreCase = true)
        }
    }
    val grouped = remember(filtered) { filtered.groupBy { it.muscleGroup } }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {},
        title = { Text("选择动作") },
        text = {
            Column {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text("搜索动作 / 肌群") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp)) {
                    grouped.forEach { (group, list) ->
                        item { Text(group, style = MaterialTheme.typography.labelMedium) }
                        items(list, key = { it.id }) { ex ->
                            TextButton(onClick = { onPick(ex) }, modifier = Modifier.fillMaxWidth()) {
                                Text(ex.name, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Start)
                            }
                        }
                    }
                }
            }
        }
    )
}

@Composable
private fun SetEditDialog(
    set: SetRecord,
    onDismiss: () -> Unit,
    onSave: (SetRecord) -> Unit,
    onDelete: () -> Unit
) {
    var weight by remember { mutableStateOf(if (set.weight % 1 == 0f) set.weight.toInt().toString() else set.weight.toString()) }
    var reps by remember { mutableStateOf(set.reps.toString()) }
    var side by remember { mutableStateOf(set.side) }
    var rpe by remember { mutableStateOf(set.rpe?.toString() ?: "") }
    var note by remember { mutableStateOf(set.note) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            Button(onClick = {
                onSave(
                    set.copy(
                        weight = weight.toFloatOrNull() ?: 0f,
                        reps = reps.toIntOrNull() ?: 0,
                        side = side,
                        rpe = rpe.toFloatOrNull(),
                        note = note
                    )
                )
            }) { Text("保存") }
        },
        dismissButton = {
            TextButton(onClick = onDelete) { Text("删除", color = MaterialTheme.colorScheme.error) }
        },
        title = { Text("编辑第 ${set.setIndex} 组") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = weight,
                        onValueChange = { weight = it },
                        label = { Text("重量(kg)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        value = reps,
                        onValueChange = { reps = it },
                        label = { Text("次数") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.weight(1f)
                    )
                }
                Text("单 / 双边", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SideButton("左", side == Side.LEFT) { side = Side.LEFT }
                    SideButton("右", side == Side.RIGHT) { side = Side.RIGHT }
                    SideButton("双手", side == Side.BOTH) { side = Side.BOTH }
                }
                OutlinedTextField(
                    value = rpe,
                    onValueChange = { rpe = it },
                    label = { Text("RPE（选填 1-10）") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("备注（选填）") },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    )
}

@Composable
private fun SideButton(label: String, selected: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.width(80.dp),
        enabled = true
    ) {
        Text(label, color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
    }
}
