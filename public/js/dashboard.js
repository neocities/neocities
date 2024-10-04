if(localStorage && localStorage.getItem('viewType') == 'list')
  $('#filesDisplay').addClass('list-view')

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

function showMovingProgress() {
  $('#movingOverlay').css('display', 'block');
}

function hideMovingProgress() {
  $('#movingOverlay').css('display', 'none');
}

function moveFile(fileName, folderName) {
  console.log(fileName);
  console.log(folderName);
  $('#moveCurrentPath').val(fileName.slice(1));
  $('#moveNewPath').val(folderName + fileName);
  $('#moveFileForm').submit();
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
    clickable: document.getElementById('uploadButton'),
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

  document.getElementById('uploadButton').addEventListener('click', function(event) {
      event.preventDefault();
  });
}

function reloadDashboardFiles() {
  var dir = $('#uploads input[name="dir"]').val();
  $.get('/dashboard/files?dir='+encodeURIComponent(dir), function(data) {
    $('#filesDisplay').html(data);
    reInitDashboardFiles();
  });
}

// for first time load
reInitDashboardFiles();
