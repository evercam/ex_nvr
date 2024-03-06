export function trackSelectedSlots(element) {
    let isMouseDown = false;
    let startTimeSlot;
    let endTimeSlot;
    const scheduleBlocks = document.querySelectorAll('.schedule-block');

    scheduleBlocks.forEach(block => {
        block.addEventListener('mousedown', (event) => {
            // Start selection
            isMouseDown = true;
            startTimeSlot = event.target;
            endTimeSlot = event.target; // Initially, selection end is the start
            event.target.classList.add('bg-sky-500');
        });

        block.addEventListener('mouseenter', (event) => {
            // Continue selection if mouse is down
            if (isMouseDown) {
                endTimeSlot = event.target;
                selectRange(startTimeSlot, endTimeSlot, scheduleBlocks, !isMouseDown);
            }
        });

        block.addEventListener('mouseup', (event) => {
            // End selection
            if (isMouseDown) {
                endTimeSlot = event.target;
                selectRange(startTimeSlot, endTimeSlot, scheduleBlocks, true); // Ensure the last block is included
                isMouseDown = false;
            }
        });
    });

    document.addEventListener('mouseup', () => {
        // In case mouseup occurred outside of any blocks
        if (isMouseDown) {
            isMouseDown = false;
            selectRange(startTimeSlot, endTimeSlot, scheduleBlocks, !isMouseDown); // Ensure the last block is included
        }
    });

    document.getElementById('cancel-task').addEventListener('click', () => {
        const taskInput = document.getElementById('task-name');

        // Hide the form
        document.getElementById('task-form').classList.add('hidden');
    
        // Clear the input fields
        document.getElementById('task-name').value = '';
        document.getElementById('start-date').value = '';
        document.getElementById('end-date').value = '';
        document.getElementById('start-time').value = '';
        document.getElementById('end-time').value = '';
    
        // Remove selection from all blocks
        document.querySelectorAll('.schedule-block.bg-sky-500').forEach(block => {
            block.classList.remove('bg-sky-500');
        });

        taskInput.blur(); //remove the focus
    });
}

function selectRange(startBlock, endBlock, blocks, isMouseUp) {
    let blocksArray = Array.from(blocks)
    let startIndex = blocksArray.indexOf(startBlock);
    let endIndex = blocksArray.indexOf(endBlock);

    // Ensure start is less than end
    if (startIndex > endIndex) {
        [startIndex, endIndex] = [endIndex, startIndex];
    }

    // Clear previous selection
    blocks.forEach(block => block.classList.remove('bg-sky-500'));
    
    // Select range
    let blocksSelected = endIndex - startIndex;

    startBlock.classList.add('bg-sky-500');
    endBlock.classList.add('bg-sky-500');

    let acc = startIndex;
    if (blocksSelected % 7 == 0){
        while(acc < endIndex)  {
            acc += 7;
            blocks[acc].classList.add('bg-sky-500');
        };
    } else {
        for (let i = startIndex; i <= endIndex; i++) {
            blocks[i].classList.add('bg-sky-500');
        }
    }

    if (isMouseUp){
        const startDate = startBlock.dataset.date;
        const endDate = endBlock.dataset.date;
        const startTime = startBlock.dataset.time;
        const endTime = endBlock.dataset.time;

        // Update form fields
        document.getElementById('start-date').value = startDate;
        document.getElementById('end-date').value = endDate;
        document.getElementById('start-time').value = startTime;
        document.getElementById('end-time').value = endTime;

        // Show the task input form
        const taskForm = document.getElementById('task-form');
        taskForm.classList.remove('hidden');

        // Position the form above the last selected block
        const formPosition = endBlock.getBoundingClientRect();
        taskForm.style.top = `${window.scrollY + formPosition.top - taskForm.offsetHeight - 10}px`; // 10px above the block
        taskForm.style.left = `${window.scrollX + formPosition.left}px`;

        // Focus on the input field
        const taskInput = document.getElementById('task-name');
        taskInput.focus();
    };
} 