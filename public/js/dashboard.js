if(localStorage && localStorage.getItem('viewType') == 'list')
  $('#filesDisplay').addClass('list-view')

function uploadFileFromButton() {
  var form = $('#uploadFilesButtonForm')[0];
  var dirValue = $('#dir').val();
  var formData = new FormData();

  // Append other form data
  formData.append('csrf_token', $(form).find('input[name="csrf_token"]').val());
  formData.append('from_button', $(form).find('input[name="from_button"]').val());
  formData.append('dir', dirValue);

  // Append files with modified filenames
  $.each($('#uploadFiles')[0].files, function(i, file) {
    var modifiedFileName = dirValue + '/' + file.name;
    formData.append(modifiedFileName, file);
  });

  // Submit the form data using jQuery's AJAX
  $.ajax({
    url: '/api/upload',
    type: 'POST',
    data: formData,
    contentType: false, // This is required for FormData
    processData: false, // This is required for FormData
    success: function(data) {
      console.log('Files successfully uploaded.');
      location.reload()
    },
    error: function(xhr, status, error) {
      console.error('Upload failed: ' + error);
      location.reload()
    }
  });
}

$('#uploadFiles').change(function() {
  $('#uploadFilesButtonForm').submit();
});

var uploadForm = $('#uploadFilesButtonForm')[0];
  var deleteForm = $('#deleteFilenameForm')[0];

  function moveFileToFolder(event) {
    var link = event.dataTransfer.getData("Text");
    if(link) link = link.trim();
    if(!link || link.startsWith('https://neocities.org/dashboard')) return;
    event.preventDefault();
    var name = link.split('.neocities.org/').slice(1).join('.neocities.org/');
    var oReq = new XMLHttpRequest();
    oReq.open("GET", "/site_files/download/" + name, true);
    oReq.responseType = "arraybuffer";
    
    $('#movingOverlay').css('display', 'block')

    oReq.onload = function() {
      var newFile = new File([oReq.response], name);
      var dataTransfer = new DataTransfer();
      var currentFolder = new URL(location.href).searchParams.get('dir');
      if(!currentFolder) currentFolder = '';
      else currentFolder = currentFolder + '/';

      dataTransfer.items.add(newFile);
      $('#uploadFilesButtonForm > input[name="dir"]')[0].value = currentFolder + event.target.parentElement.parentElement.getElementsByClassName('title')[0].innerText.trim();
      $('#uploadFiles')[0].files = dataTransfer.files;
      $.ajax({
        type: uploadForm.method,
        url: uploadForm.action,
        data: new FormData(uploadForm),
        processData: false,
        contentType: false,
        success: function() {
          let csrf = $('#uploadFilesButtonForm > input[name="csrf_token"]')[0].value;
          var dReq = new XMLHttpRequest();
          dReq.open(deleteForm.method, deleteForm.action, true);
          dReq.onload = function() {
            location.reload()
          }
          dReq.setRequestHeader("content-type", 'application/x-www-form-urlencoded');
          dReq.send("csrf_token=" + encodeURIComponent(csrf) + "&filename=" + name.replace(/\s/g, '+'));
        },
        error: function() {
          location.reload()
        }
      });
    };
    oReq.send();
  }

  function confirmFileRename(path) {
    console.log(path)
    $('#renamePathInput').val(path);
    $('#renameNewPathInput').val(path);
    $('#renameModal').modal();
  }

  function confirmFileDelete(name) {
    $('#deleteFileName').text(name);
    $('#deleteConfirmModal').modal();
  }

  function fileDelete() {
    $('#deleteFilenameInput').val($('#deleteFileName').html());
    $('#deleteFilenameForm').submit();
  }

  function clickUploadFiles() {
    $("input[id='uploadFiles']").click()
  }

  function showUploadProgress() {
    $('#uploadingOverlay').css('display', 'block')
  }

  function hideUploadProgress() {
    $('#progressBar').css('display', 'none')
    $('#uploadingOverlay').css('display', 'none')
  }


/*
      this.on("totaluploadprogress", function(progress, totalBytes, totalBytesSent) {
        if(progress == 100)
          allUploadsComplete = true

        showUploadProgress()
        $('#progressBar').css('display', 'block')
        $('#uploadingProgress').css('width', progress+'%')
      })
*/

  allUploadsComplete = false

  $('#createDir').on('shown', function () {
    $('#newDirInput').focus();
  })

  $('#createFile').on('shown', function () {
    $('#newFileInput').focus();
  })

  function listView() {
    if(localStorage)
      localStorage.setItem('viewType', 'list')

    $('#filesDisplay').addClass('list-view')
  }

  function iconView() {
    if(localStorage)
      localStorage.removeItem('viewType')

    $('#filesDisplay').removeClass('list-view')
  }







// Drop handler function to get all files
async function getAllFileEntries(dataTransferItemList) {
  let fileEntries = [];
  // Use BFS to traverse entire directory/file structure
  let queue = [];
  for (let i = 0; i < dataTransferItemList.length; i++) {
    queue.push(dataTransferItemList[i].webkitGetAsEntry());
  }
  while (queue.length > 0) {
    let entry = queue.shift();
    if (entry.isFile) {
      fileEntries.push(entry);
    } else if (entry.isDirectory) {
      let reader = entry.createReader();
      queue.push(...await readAllDirectoryEntries(reader));
    }
  }
  return fileEntries;
}

// Get all the entries (files or sub-directories) in a directory
async function readAllDirectoryEntries(directoryReader) {
  let entries = [];
  let readEntries = await readEntriesPromise(directoryReader);
  while (readEntries.length > 0) {
    entries.push(...readEntries);
    readEntries = await readEntriesPromise(directoryReader);
  }
  return entries;
}

// Wrap readEntries in a promise
async function readEntriesPromise(directoryReader) {
  try {
    return await new Promise((resolve, reject) => {
      directoryReader.readEntries(resolve, reject);
    });
  } catch (err) {
    console.log(err);
  }
}

async function uploadFile(file, dir, additionalFormData) {
  const formData = new FormData();

  // Append additional form data (from other input fields) to each file's FormData
  for (const [key, value] of Object.entries(additionalFormData)) {
    formData.append(key, value);
  }

  // Append the file to the FormData, using the file name as key
  var modifiedFileName = dir + '/' + file.webkitRelativePath || file.name;
  formData.append(modifiedFileName, file, modifiedFileName);

  $('#uploadFileName').text(modifiedFileName).prepend('<i class="icon-file"></i> ');

  // Send the FormData with the file and additional data
  try {
    const response = await fetch('/api/upload', {
      method: 'POST',
      body: formData,
    });
    const result = await response.json();
    console.log('Upload successful for', file.name, result);
  } catch (err) {
    console.error('Upload error for', file.name, err);
  }
}

async function processEntry(entry, dir, additionalFormData) {
  await new Promise((resolve) => {
    entry.file((file) => {
      uploadFile(file, dir, additionalFormData).then(resolve);
    });
  });
}

async function uploadFiles(fileEntries) {
  // Collect additional form data
  const form = document.getElementById('dropzone');
  let additionalFormData = {};
  for (let i = 0; i < form.elements.length; i++) {
    const input = form.elements[i];
    if (input.name && input.type !== "file") { // Avoid file inputs
      additionalFormData[input.name] = input.value;
    }
  }
  
  const dir = additionalFormData['dir'] || '';

  var totalFiles = fileEntries.length;
  $('#progressBar').css('display', 'block')

  fileUploadCount = 0

  for (let entry of fileEntries) {
    await processEntry(entry, dir, additionalFormData);
    fileUploadCount++;
    var progress = (fileUploadCount / totalFiles) * 100;
    $('#uploadingProgress').css('width', progress+'%');
  }

  allUploadsComplete = true
  location.reload();
}

var elDrop = document.getElementById('dropzone');

elDrop.addEventListener('dragover', function (event) {
  event.preventDefault();
});

elDrop.addEventListener('drop', async function (event) {
  event.preventDefault();
  showUploadProgress();
  let items = await getAllFileEntries(event.dataTransfer.items);
  await uploadFiles(items);
});
