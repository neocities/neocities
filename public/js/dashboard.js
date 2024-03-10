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

  uploadFilesCount = 0
  // Append files with modified filenames
  $.each($('#uploadFiles')[0].files, function(i, file) {
    var modifiedFileName = dirValue + '/' + file.name;
    formData.append(modifiedFileName, file);
    uploadFilesCount++;
  });

  alertClear();

  $.ajax({
    url: '/api/upload',
    type: 'POST',
    data: formData,
    contentType: false, // This is required for FormData
    processData: false, // This is required for FormData
    success: function(data) {
      alertType('success');
      alertAdd(uploadFilesCount+' files uploaded successfully.');
      reloadDashboardFiles();
    },
    error: function(xhr, status, error) {
      var responseBody = JSON.parse(xhr.responseText);
      alertType('error');
      alertAdd(responseBody.message);
      reloadDashboardFiles();
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

function alertAdd(text) {
  var a = $('#alertDialogue');
  a.css('display', 'block');
  a.append(text+'<br>');
}

function alertClear(){
  var a = $('#alertDialogue');
  a.css('display', 'none');
  a.text('');
}

function alertType(type){
  var a = $('#alertDialogue');
  a.removeClass('alert-success');
  a.removeClass('alert-error');
  a.addClass('alert-'+type);
}

var processedFiles = 0;
var uploadedFiles = 0;
var uploadedFileErrors = 0;

function joinPaths(...paths) {
  return paths
    .map(path => path.replace(/(^\/|\/$)/g, ''))
    .filter(path => path !== '')
    .join('/');
}

function reInitDashboardFiles() {
  new Dropzone("#uploads", {
    url: "/api/upload",
    paramName: 'file',
    dictDefaultMessage: "",
    uploadMultiple: false,
    parallelUploads: 1,
    maxFilesize: 104857600, // 100MB
    clickable: false,

    init: function() {
      this.on("processing", function(file) {
        var dir = $('#uploads input[name="dir"]').val();
        if(file.fullPath) {
          this.options.paramName = joinPaths(dir,file.fullPath);
        } else {
          this.options.paramName = joinPaths(dir, file.name);
        }

        processedFiles++;
        $('#uploadFileName').text(this.options.paramName).prepend('<i class="icon-file"></i> ');
      });

      this.on("success", function(file) {
        uploadedFiles++;
      });

      this.on("error", function(file, message) {
        uploadedFiles++;
        uploadedFileErrors++;
        alertType('error');
        if (message && message.message) {
          alertAdd(message.message);
        } else {
          alertAdd(this.options.paramName+' failed to upload');
        }
      });

      this.on("queuecomplete", function() {
        hideUploadProgress();
        if(uploadedFileErrors > 0) {
          alertType('error');
          alertAdd(uploadedFiles-uploadedFileErrors+'/'+uploadedFiles+' files uploaded successfully');
        } else {
          alertType('success');
          alertAdd(uploadedFiles+' files uploaded successfully');
        }
        reloadDashboardFiles();
      });

      this.on("addedfiles", function(files) {
        uploadedFiles = 0;
        uploadedFileErrors = 0;
        alertClear();
        showUploadProgress();
      });
    }
  });
}

function reloadDashboardFiles() {
  $.get('/dashboard/files?dir='+encodeURIComponent($("#dir").val()), function(data) {
    $('#filesDisplay').html(data);
    reInitDashboardFiles();
  });
}

// for first time load
reInitDashboardFiles();



